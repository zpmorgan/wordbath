package Wordbath::Transcript::AudioSync;
use Moose;

{
  package Wordbath::Transcript::AudioSync::Anchor;
  use Moose;
  has mark => (is => 'ro', isa => 'Gtk3::TextMark', required => 1);
  has pos_ns => (is => 'ro', isa => 'Int', required => 1);
  has time_placed => (is => 'ro', isa => 'Int', default => sub{time});
  sub pos_chars{
    my $self = shift;
    my $textiter = $self->mark->get_buffer->get_iter_at_mark ($self->mark);
    my $chars = $textiter->get_offset;
    return $chars;
  }

}

# TODO: anchor stuff might belong in Wordbath::SpaceTime :)
has _pseuso_anchors => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub{[]},
  traits => ['Array'],
  handles => {
    _pseudo_anchor_push => 'push',
  },
);
has transcript => (weak_ref => 1, isa => 'Wordbath::Transcript', is => 'ro');
no Moose;
# conflicts with PDL's  'inner' exported symbol

sub anchor_here_at{
  my $self = shift;
  my %args = @_;
  die 'need time. '.@_ unless $args{pos_ns};
  die 'need mark. '.@_ unless $args{mark};
  my $pa = Wordbath::Transcript::AudioSync::Anchor->new(pos_ns => $args{pos_ns}, mark => $args{mark});
  $self->_pseudo_anchor_push($pa);
}

use PDL;

#x is audio nanoseconds, y (predicted) is basically character offset in text
sub iter_at_audio_pos{
  my ($self, $pos_ns) = @_;
  my @anchors = @{$self->_pseuso_anchors};
  my $buf = $self->transcript->_buf;
  return $buf->get_start_iter if (@anchors == 0);
  @anchors = sort {$a->pos_ns <=> $b->pos_ns} @anchors;
  # PDL interpolate breaks with duplicates.
  my %uniq;
  @anchors = grep {!$uniq{$_->pos_ns}++} @anchors;

  my $x = float(map {$_->pos_ns} @anchors);
  my $y = float(map {$_->pos_chars} @anchors);
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

  my @anchors = @{$self->_pseuso_anchors};
  return 0 if (@anchors == 0);
  my %uniq;
  @anchors = grep {!$uniq{$_->pos_chars}++} @anchors;
  @anchors = sort {$a->pos_chars <=> $b->pos_chars} @anchors;

  my $x = float(map {$_->pos_chars} @anchors);
  my $y = float(map {$_->pos_ns} @anchors);
  my $xi = pdl($iter->get_offset);
  my $pos_ns = $xi->interpol($x,$y);
  return $pos_ns->sclr;
}
1;
