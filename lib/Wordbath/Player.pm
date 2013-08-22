package Wordbath::Player;
use Moose;
use Modern::Perl;
use GStreamer -init;
use FindBin '$Bin';
use Carp;

#gstreamer stuff in this module.
#todo: subband sinusoidal modeling?

sub LOG{
  my ($cat, $msg) = @_;
}
sub DEBUG{
  my ($msg) = @_;
  LOG(debug => $msg);
}
sub GST_LOG{
  my ($msg) = @_;
  LOG(gstreamer => $msg);
}

sub BILLION{10**9}

has _rate => (
  isa => 'Num',
  is => 'rw',
  default => 1,
);

has pipeline => (
  isa => 'GStreamer::Pipeline',
  is => 'ro',
  lazy => 1,
  builder => '_build_pipeline',
);

# these are all created by the pipeline builder.
has [qw/_nl_src _audio_out _dec _stretcher_element/] => (
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
      GST_LOG ($msg->src .' state changed: ' . $msg->old_state .'  ===>  '. $msg->new_state);
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

sub get_rate{
  my $self = shift;
  $self->_rate();
}

sub set_rate{
  my ($self, $rate) = @_;
  my $pos = $self->pos_ns();
  $pos = 0 unless $pos;
  GST_LOG ("Seeking: pos is $pos, new rate is $rate.");
  $self->pipeline->seek($rate, 'time', [qw/flush accurate/], set => $pos, none => -1);
  $self->_rate($rate);
}

sub seek_sec{
  my ($self, $sec) = @_;
  $self->seek_ns($sec * 10**9);
}
sub seek_ns{
  my ($self, $ns) = @_;
  GST_LOG "seeking to ns $ns.";
  $self->pipeline->seek($self->_rate, 'time', [qw/flush accurate/], set => $ns, none => -1);
}
sub shift_seconds{
  my ($self, $sec) = @_;
  GST_LOG "relative seek $sec seconds.";
  $self->pipeline->seek($self->_rate, 'time', [qw/flush accurate/],
    set => $self->pos_ns + $sec*10**9,
    none => -1);
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
  else {
    confess 'could not query duration.';
  }
}
sub print_status{
  my $self = shift;
  warn 'FOO';
}

sub _load_audio_file{
  my ($self,$f) = @_;
  $self->pipeline;
  # src.set_property('uri', 'file:///my/cool/video')
  my $pathuri = "file://$Bin/$f";
  GST_LOG "loading URI: $pathuri";
  $self->_nl_src->set(location => $f);
  $self->pipeline->set_state('paused');
  $self->pipeline->get_state(10**9);
}
sub play{
  my ($self) = @_;
  $self->pipeline->set_state('playing');
  #$self->_nl_src->set('media-start' => 0);
  #$self->_nl_src->set('media-duration' => 5*BILLION);
  GST_LOG 'PLAYING';
}
sub shut_down{
  my ($self) = @_;
  $self->pipeline->set_state('null');
  GST_LOG 'SHUTTING DOWN. (pipeline state to null.)';
}
sub toggle_play_state{
  my ($self) = @_;
  my @state = ($self->pipeline->get_state(10**9));
  GST_LOG 'TOGGLING. '. $state[1];
  if ($state[1] eq 'playing'){
    $self->pipeline->set_state('paused');
  } else {
    $self->pipeline->set_state('playing');
  }
}

1;
