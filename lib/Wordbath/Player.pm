package Wordbath::Player;
use Moose;
use GStreamer -init;
use FindBin '$Bin';

#gstreamer stuff.
sub DEBUG{};

has pipeline => (
  isa => 'GStreamer::Pipeline',
  is => 'ro',
  lazy => 1,
  builder => '_build_pipeline',
);

my $fsrc;


sub _build_pipeline{
  my $self = shift;
  my $p = GStreamer::Pipeline->new('pipe_in');
  my $b = GStreamer::Bin->new('bin_in');
  my $bus = $p->get_bus();
  $bus->add_signal_watch;
  $bus->signal_connect('message::error', sub{
      my ($bus,$msg) = @_;
      warn 'err: ' . $msg->error;
    });
  $bus->signal_connect('message::state-changed', sub{
      my ($bus,$msg) = @_;
      DEBUG ('state changed: ' . $msg->old_state .'  ===>  '. $msg->new_state);
    });

  my ($decoder,$end);
  ($fsrc,$decoder,$end) =
  map { GStreamer::ElementFactory->make($_ => $_) }
    qw/filesrc decodebin2  autoaudiosink/;
  $p->add ($fsrc,$decoder,$end);
  $fsrc->link($decoder);
  $decoder->link($end);
  $decoder->signal_connect ('pad-added' => sub{
      my ($bin,$pad) = @_;
      my $snk = $end->get_pad('sink');
      return if $snk->is_linked();
      $pad->link($snk);
    });
  return $p;
}

sub load_audio_file{
  my ($self,$f) = @_;
  $self->pipeline;
  DEBUG "loading $f";
  $fsrc->set(location => $f);

  #my $file= '/dchha48_Prophets_of_Doom.mp3';
  #my $path = $Bin . '/' . $file;
  #$omnibin-> set(uri => Glib::filename_to_uri $path, "localhost");
}
sub play{
  my ($self) = @_;
  $self->pipeline->set_state('playing');
  DEBUG 'PLAYING';
}
sub shut_down{
  my ($self) = @_;
  $self->pipeline->set_state('null');
  DEBUG 'SHUTTING DOWN';
}

1;
