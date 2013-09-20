package Wordbath::Transcript::AudioSync;
use Moose;
#with 'Wordbath::Transcript::AudioSync::Role::Interpolate';

{
  package Wordbath::Transcript::AudioSync::SyncVector;
  use Moose;
  has mark => (is => 'ro', isa => 'Gtk3::TextMark', required => 1);
  has pos_ns => (is => 'ro', isa => 'Int', required => 1);
  has time_placed => (is => 'ro', isa => 'Int', default => sub{time});
  # slabel, ile, on-stop, on-go
  has type => (is => 'ro', isa => 'Str', default => 'none');
  sub pos_chars{
    my $self = shift;
    my $textiter = $self->mark->get_buffer->get_iter_at_mark ($self->mark);
    my $chars = $textiter->get_offset;
    return $chars;
  }

  __PACKAGE__->meta->make_immutable;
}

has _sync_vectors => (
  is => 'rw',
  isa => 'ArrayRef',
  traits => ['Array'],
  handles => {
    _sync_vector_push => 'push',
  },
  lazy => 1,
  builder => '_build_sync_vectors',
);
has transcript_model => (weak_ref => 1, isa => 'Wordbath::Transcript::Model', is => 'ro');
has player => (weak_ref => 1, isa => 'Wordbath::Player', is => 'rw'); #please set this.
#has model => (isa => 'Wordbath::Player', is => 'ro', model=>'_build_model');

has _mark_inc => (
  is=>'rw', isa=>'Int', default=>0,
  traits=>['Counter'],
  handles => {_inc_mark_inc=> 'inc'} );
has _vecs_by_mark_name => (
  isa => 'HashRef', is=>'ro', default=>sub{{}} );

sub build_model{
  my $self = shift;
  my $model = Wordbath::Transcript::AudioSync::Model::Interpolate_with_culling->new(
    sync => $self,
  );
  $model->apply_all_roles(
    'Wordbath::Transcript::AudioSync::Model::Interpolate',
    'Wordbath::Transcript::AudioSync::Model::Interpolate_with_culling',
  );
  return $model;
}

sub _build_sync_vectors{
  my $self = shift;
  return [];
}
sub buf{
  my $self = shift;
  return $self->transcript_model->buf;
}
sub vector_here_at{
  my $self = shift;
  my %args = @_;
  #die 'need time. '.@_ unless $args{pos_ns};
  die 'need SVector type. '.@_ unless $args{type};
  unless ($args{pos_ns}){
    $args{pos_ns} = $self->player->pos_ns;
  }
  die 'need iter. '.@_ unless $args{iter};
  my $mark = $self->buf->create_mark('vec '.$self->_inc_mark_inc, $args{iter}, 1);
  my $vec = Wordbath::Transcript::AudioSync::SyncVector->new(
    type => $args{type},
    pos_ns => $args{pos_ns},
    mark => $mark,
  );
  $self->_vecs_by_mark_name->{$mark->get_name} = $vec;
  $self->_sync_vector_push($vec);
}

sub vector_from_mark{
  my ($self, $mark) = @_;
  return unless $mark->get_name;
  my $vec = $self->_vecs_by_mark_name->{$mark->get_name};
  return $vec;
}

sub guess_textiter_from_pos_ns{0}
sub guess_pos_ns_from_textiter{0}

{
  package Wordbath::Transcript::AudioSync::Role::Interpolate;
  use Moose::Role;

  around 'guess_textiter_from_pos_ns' => sub{
    my $orig = shift;
    my $self = shift;
    return $self->interpolate_textiter_from_pos_ns(@_);
  };
  around 'guess_pos_ns_from_textiter' => sub{
    my $orig = shift;
    my $self = shift;
    return $self->interpolate_pos_ns_from_textiter(@_);
  };

  no Moose::Role;
  use PDL;
  #x is audio nanoseconds, y (predicted) is basically character offset in text
  sub interpolate_textiter_from_pos_ns{
    my ($self, $pos_ns) = @_;
    #my $sync = $self->sync;
    my @SVs = @{$self->_sync_vectors};
    my $buf = $self->transcript_model->buf;
    return $buf->get_start_iter if (@SVs == 0);
    @SVs = sort {$a->pos_ns <=> $b->pos_ns} @SVs;
    # PDL interpolate breaks with duplicates.
    my %uniq;
    @SVs = grep {!$uniq{$_->pos_ns}++} @SVs;

    my $x = float(map {$_->pos_ns} @SVs);
    my $y = float(map {$_->pos_chars} @SVs);
    my $xi = float($pos_ns);
    my ($yi,$err) = $xi->interpol($x, $y);
    # currently this warns on interpolation, and probably doesn't do it right.
    my $iter = $buf->get_iter_at_offset ($yi->floor->sclr);
    return $iter;
  }
  sub interpolate_pos_ns_from_textiter{
    my ($self, $iter) = @_;
    #my $sync = $self->sync;
    $iter = $self->transcript_model->cursor_iter unless $iter;

    my @SVs = @{$self->_sync_vectors};
    return 0 if (@SVs == 0);
    my %uniq;
    @SVs = grep {!$uniq{$_->pos_chars}++} @SVs;
    @SVs = sort {$a->pos_chars <=> $b->pos_chars} @SVs;

    my $x = float(map {$_->pos_chars} @SVs);
    my $y = float(map {$_->pos_ns} @SVs);
    my $xi = pdl($iter->get_offset);
    my $pos_ns = $xi->interpol($x,$y);
    return $pos_ns->sclr;
  }
}
{
  package Wordbath::Transcript::AudioSync::Role::Interpolate_with_culling;
  use Moose::Role;
  requires ('interpolate_pos_ns_from_textiter', 'interpolate_textiter_from_pos_ns');
  around 'guess_textiter_from_pos_ns' => sub{
    my $orig = shift;
    my $self = shift;
    return $self->culling_interpolate_textiter_from_pos_ns(@_);
  };
  around 'guess_pos_ns_from_textiter' => sub{
    my $orig = shift;
    my $self = shift;
    return $self->culling_interpolate_pos_ns_from_textiter(@_);
  };
  sub culling_interpolate_pos_ns_from_textiter{
    my $self = shift;
    return $self->interpolate_pos_ns_from_textiter(@_);
  }
  sub culling_interpolate_textiter_from_pos_ns{
    my $self = shift;
    return $self->interpolate_textiter_from_pos_ns(@_);
  }
}
with 'Wordbath::Transcript::AudioSync::Role::Interpolate';
with 'Wordbath::Transcript::AudioSync::Role::Interpolate_with_culling';

1;
