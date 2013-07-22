package Wordbath::Player;
use Moose;
use Modern::Perl;
use GStreamer -init;
use FindBin '$Bin';

#gstreamer stuff.
#todo: subband sinusoidal modeling?
sub DEBUG{}
sub BILLION{10**9}

has pos_nsFOO => (
  isa => 'Int',
  is => 'rw',
  default => 30 * BILLION,
);

has pipeline => (
  isa => 'GStreamer::Pipeline',
  is => 'ro',
  lazy => 1,
  builder => '_build_pipeline',
);

has _nl_src => (
  isa => 'GStreamer::Element',
  is => 'rw',
);
has _audio_out => (
  isa => 'GStreamer::Element',
  is => 'rw',
);
has [qw/_dec _stretcher_element/] => (
  isa => 'GStreamer::Element',
  is => 'rw',
);

my $fsrc;

sub _build_pipeline{
  my $self = shift;
  ##my $p = GStreamer::Pipeline->new('pipe_in');
  my $pipeline = GStreamer::parse_launch(
    #   "gnlurisource name=gnlsrc ! ".
    "filesrc name=gnlsrc ! decodebin2 name=derc !".
    "queue ! audioconvert ! audioresample ! ".
    "scaletempo name=stempo ! ".
    "audioconvert ! audioresample ! ".
    "autoaudiosink name=speakers");
  my $gnlsrc = $pipeline->get_by_name('gnlsrc');
  my $stempo = $pipeline->get_by_name('stempo');
  my $speakers= $pipeline->get_by_name('speakers');
  my $dec= $pipeline->get_by_name('derc');

  my $bus = $pipeline->get_bus();
  $bus->add_signal_watch;
  $bus->signal_connect('message::error', sub{
      my ($bus,$msg) = @_;
      warn 'err: ' . $msg->error;
    });
  $bus->signal_connect('message::state-changed', sub{
      my ($bus,$msg) = @_;
      say ($msg->src .' state changed: ' . $msg->old_state .'  ===>  '. $msg->new_state);
    });
  #$self->_nl_src->link($self->_stretcher_element);
  #$self->_stretcher_element->link($self->_audio_out);
  $gnlsrc->signal_connect ('pad-added' => sub{
      warn 'New pad.';
      my ($bin,$pad) = @_;
      my $snk = $dec->get_pad('sink');
      if ($snk->is_linked()){
        warn 'Pad already linked' if $snk->is_linked();
        return;
      }
      $pad->link($snk);
    });

  $self->_audio_out( $speakers );
  $self->_nl_src( $gnlsrc );
  $self->_stretcher_element( $stempo );
  $self->_dec( $dec);
  return $pipeline;
}

sub set_rate{
  my ($self, $rate) = @_;
  my $pos = $self->pos_ns();
  $pos = 0 unless $pos;
  say "Seeking: pos is $pos, new rate is $rate.";
  $self->pipeline->seek($rate, 'time', [qw/segment flush accurate/], set => $pos, none => -1);
}

sub pos_ns{
  my $self = shift;
  my $q = GStreamer::Query::Position->new('time');
  my $success = $self->pipeline->query($q);
  #warn "$res res, pos ". ($q->position)[1];
  if ($success){
    my $pos = ($q->position)[1];
    return $pos;
  }
}
sub dur_ns{
  my $self = shift;
  my $q = GStreamer::Query::Duration->new('time');
  my $success = $self->pipeline->query($q);
  if ($success){
    my $dur= ($q->duration)[1];
    return $dur;
  }
}
sub print_status{
  my $self = shift;
  warn 'FOO';
}

sub load_audio_file{
  my ($self,$f) = @_;
  $self->pipeline;
  # src.set_property('uri', 'file:///my/cool/video')
  my $pathuri = "file://$Bin/$f";
  warn "loading URI: $pathuri";
  $self->_nl_src->set(location => $f);
}
sub play{
  my ($self) = @_;
  $self->pipeline->set_state('playing');
  #$self->_nl_src->set('media-start' => 0);
  #$self->_nl_src->set('media-duration' => 5*BILLION);
  DEBUG 'PLAYING';
}
sub shut_down{
  my ($self) = @_;
  $self->pipeline->set_state('null');
  DEBUG 'SHUTTING DOWN';
}

1;
