package Wordbath::Player;
use Moose;
use Modern::Perl;
use GStreamer -init;
use FindBin '$Bin';
use Carp 'cluck';

my ($major, $minor, $micro) = GStreamer -> version();
#gstreamer stuff in this module.
#todo: subband sinusoidal modeling?

with 'Wordbath::Roles::Logger';

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

has x_overlay => (
  is => 'rw',
  isa => 'GStreamer::Element',
  predicate => 'has_video',
);

my $fsrc;

sub _build_pipeline{
  my $self = shift;
  # newer gstreamer uses videoconvert instead of ffmpegcolorspace?
  # also, it doesn't fail on parse errors?
  my $pipeline_description =
    "filesrc name=my_file_src ! typefind name=typer ! fakesink name=fake ".
    "decodebin2 name=derc ".
    # all media is assumed to contain audio. that's the point.
    "derc. ! queue ! audioconvert ! audioresample ! ".
    "scaletempo name=stempo ! ".
    "audioconvert ! audioresample ! ".
    "autoaudiosink name=speakers ";

  my $pipeline = GStreamer::parse_launch( $pipeline_description);
  #autovideosink async-handling=true");
  my $my_file_src = $pipeline->get_by_name('my_file_src');
  my $stempo = $pipeline->get_by_name('stempo');
  my $speakers= $pipeline->get_by_name('speakers');
  my $dec= $pipeline->get_by_name('derc');
  my $fake= $pipeline->get_by_name('fake');

  # create video elements if the media is found to contain video.
  my $typer = $pipeline->get_by_name('typer');
  $typer->signal_connect('have-type' => sub{
      my ($tfind, $probability, $caps) = @_;
      $self->logger->INFO ("CAPS: $caps");
      if ($caps =~ /^video/){
        $self->logger->INFO ("doing video pipeline things");
        my $conv  = GStreamer::ElementFactory->make(
          ($major<1 ? 'ffmpegcolorspace' : 'videoconvert') => 'vconv');
        my $vsink = GStreamer::ElementFactory->make(autovideosink => 'vsink');
        $self->x_overlay($vsink);
        $pipeline->add($conv,$vsink);
        $conv->link($vsink) or die "vconv/sink linklessness";
        $dec->signal_connect ('pad-added' => sub{
            my ($bin,$pad) = @_;
            # huh? we're assuming that this is video?
            $self->logger->INFO ('New pad on decodebin2 for video...');
            my $snk = $conv->get_static_pad('sink');
            if ($snk->is_linked()){
              warn 'Pad already linked' if $snk->is_linked();
              return;
            }
            $pad->link($snk);
          });
      }
      $my_file_src->unlink($typer);
      $typer->unlink($fake);
      $pipeline->remove($typer);
      $pipeline->remove($fake);
      $my_file_src->link($dec);
      $pipeline->get_state(10**9);
    });

  my $bus = $pipeline->get_bus();
  $bus->add_signal_watch;
  $bus->signal_connect('message::warning', sub{
      my ($bus,$msg) = @_;
      warn 'warn: ' . $msg->warning;
    });
  $bus->signal_connect('message::error', sub{
      my ($bus,$msg) = @_;
      warn 'err: ' . $msg->error;
    });
  $bus->signal_connect('message::state-changed', sub{
      my ($bus,$msg) = @_;
      $self->logger->DEBUG('GST  ' . $msg->src .' state changed: ' . $msg->old_state .'  ===>  '. $msg->new_state);
    });
  $my_file_src->signal_connect ('pad-added' => sub{
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
  $self->_nl_src( $my_file_src );
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
  $self->logger->DEBUG('GST  ' . "Seeking: pos is $pos, new rate is $rate.");
  $self->pipeline->seek($rate, 'time', [qw/flush accurate/], set => $pos, none => -1);
  $self->_rate($rate);
}

sub seek_sec{
  my ($self, $sec) = @_;
  $self->seek_ns($sec * 10**9);
}
sub seek_ns{
  my ($self, $ns) = @_;
  $self->logger->DEBUG('GST  ' . "seeking to ns $ns.");
  $self->pipeline->seek($self->_rate, 'time', [qw/flush accurate/], set => $ns, none => -1);
}
sub shift_seconds{
  my ($self, $sec) = @_;
  $self->logger->DEBUG('GST  ' .  "relative seek $sec seconds.");
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
  warn 'could not query duration.';
  return 0
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
  $self->logger->DEBUG('GST  ' .  "loading URI: $pathuri");
  $self->_nl_src->set(location => $f);
  $self->pipeline->set_state('playing');
  warn $self->pipeline->get_state(10**9);
}
sub play{
  my ($self) = @_;
  $self->pipeline->set_state('playing');
  #$self->_nl_src->set('media-start' => 0);
  #$self->_nl_src->set('media-duration' => 5*BILLION);
  $self->logger->DEBUG('GST  ' .  'PLAYING');
}
sub shut_down{
  my ($self) = @_;
  $self->pipeline->set_state('null');
  $self->logger->DEBUG('GST  ' . 'SHUTTING DOWN. (pipeline state to null.)');
}
sub toggle_play_state{
  my ($self) = @_;
  my @state = ($self->pipeline->get_state(10**9));
  my $new_state = ($state[1] eq 'playing') ? 'paused' : 'playing';
  $self->pipeline->set_state($new_state);
  $self->logger->DEBUG('GST  ' .  'TOGGLING. '. $state[1] . ' to ' . $new_state);
  return $new_state;
}

1;
