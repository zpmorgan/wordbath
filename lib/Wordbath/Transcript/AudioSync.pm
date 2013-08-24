package Wordbath::Transcript::AudioSync;
use Moose;

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
  builder => '_root_sync_vectors',
);
has transcript => (weak_ref => 1, isa => 'Wordbath::Transcript', is => 'ro');
has player => (weak_ref => 1, isa => 'Wordbath::Player', is => 'rw'); #please set this.
no Moose;
# conflicts with PDL's  'inner' exported symbol


sub _root_sync_vectors{
  my $self = shift;
  my $buf = $self->transcript->_buf;
  my ($si,$ei) = $buf->get_bounds;
  my $s = $buf->create_mark("start pa", $si, 1);
  my $e = $buf->create_mark("end pa",   $ei, 1);
  my $spa = Wordbath::Transcript::AudioSync::SyncVector->new(type => '-ile',
        pos_ns => 0, mark => $s);
  my $epa = Wordbath::Transcript::AudioSync::SyncVector->new(type => '-ile',
        pos_ns => $self->player->dur_ns, mark => $e);
  return [$spa, $epa];
}

sub vector_here_at{
  my $self = shift;
  my %args = @_;
  #die 'need time. '.@_ unless $args{pos_ns};
  die 'need SVector type. '.@_ unless $args{type};
  unless ($args{pos_ns}){
    $args{pos_ns} = $self->player->pos_ns;
  }
  die 'need mark. '.@_ unless $args{mark};
  my $pa = Wordbath::Transcript::AudioSync::SyncVector->new(
    type => $args{type},
    pos_ns => $args{pos_ns},
    mark => $args{mark}
  );
  $self->_sync_vector_push($pa);
}

use PDL;

#x is audio nanoseconds, y (predicted) is basically character offset in text
sub iter_at_audio_pos{
  my ($self, $pos_ns) = @_;
  my @SVs = @{$self->_sync_vectors};
  my $buf = $self->transcript->_buf;
  return $buf->get_start_iter if (@SVs == 0);
  @SVs = sort {$a->pos_ns <=> $b->pos_ns} @SVs;
  # PDL interpolate breaks with duplicates.
  my %uniq;
  @SVs = grep {!$uniq{$_->pos_ns}++} @SVs;

  my $x = float(map {$_->pos_ns} @SVs);
  my $y = float(map {$_->pos_chars} @SVs);
  my $xi = float($pos_ns);
  my ($yi,$err) = $xi->interpol($x, $y);
  # currently this warns on extrapolation, and probably doesn't do it right.
  my $iter = $buf->get_iter_at_offset ($yi->floor->sclr);
  return $iter;
}
sub audio_pos_ns_at{
  my $self = shift;
  my $iter = shift;
  $iter = $self->transcript->cursor_iter unless $iter;

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

use JSON;
sub serialize{
  my $self = shift;
  return encode_json {};
}
1;
