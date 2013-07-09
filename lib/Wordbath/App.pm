package Wordbath::App;
use Moose;
use GStreamer -init;
use Gtk3 -init;
use FindBin '$Bin';

my $LOOP; # ?
$LOOP = Glib::MainLoop->new();

#gtk3 & gstreamer stuff.

has win => (
  isa => 'Gtk3::Window',
  is => 'ro',
  lazy => 1,
  builder => '_build_win',
);

has _text_widget => (
  isa => 'Gtk3::TextView',
  is => 'rw',
);

sub _build_win{
  my $self = shift;
  my $win = Gtk3::Window->new();
  $win->set_title('Wordbath');
  $win->set_border_width(0);
  $win->set_size_request(600,400);
  my $accel_group = Gtk3::AccelGroup->new;
  $win->add_accel_group($accel_group);
  $win->signal_connect (destroy => sub { $LOOP->quit });

  {
    my $vbox = Gtk3::Box->new('vertical', 3);
    my $menubar = Gtk3::MenuBar->new();
    my $menuitem = Gtk3::MenuItem->new_with_label('foo');
    $menubar->append($menuitem);
    my $button1 = Gtk3::Button->new ('Quit');
    my $button2 = Gtk3::Button->new ('foo');

    my $pbar = Gtk3::ProgressBar->new();
    my $scrolled_text_stuff = Gtk3::ScrolledWindow->new();
    {
      $scrolled_text_stuff->set_vexpand(1);
      $scrolled_text_stuff->set_hexpand(0);
      my $wordbox = Gtk3::TextView->new();
      $wordbox->set_wrap_mode('word');
      $self->_text_widget($wordbox);
      $scrolled_text_stuff->add($wordbox)
    }

    $win->add($vbox);
    $vbox->pack_start($menubar, 0,0,0);
    $vbox->pack_start($pbar, 0,0,0);
    $vbox->pack_start($button1, 0,0,0);
    $vbox->pack_start($button2, 0,0,0);
    $vbox->pack_start($scrolled_text_stuff, 1,1,0);
  }
  $win->show_all();
  return $win;
}

sub run{
  my $self = shift;
  $self->win;
  $LOOP->run();
  #Gtk3::main;
}

my $omnibin;

has pipeline => (
  isa => 'GStreamer::Pipeline',
  is => 'ro',
  lazy => 1,
  builder => '_build_pipeline',
);

sub _build_pipeline{
  my $self = shift;
  my $p = GStreamer::Pipeline->new('pipe_in');
  my $b = GStreamer::Bin->new('bin_in');
  my ($src,$decodebin,$end);

  ($src,$decodebin,$end, $omnibin) =
  map { GStreamer::ElementFactory->make($_ => $_) }
    qw/filesrc decodebin  pulsesink playbin2/;
  $p->add ($src,$decodebin,$end);
  my $bus = $p->get_bus();
  $bus->signal_connect('message::error', sub{warn @_, "\n"}, 1);
  $bus->signal_connect('message::state-changed', sub{warn @_, "\n"}, 1);
  return $p;
}

sub load_audio_file{
  my ($self,$f) = @_;
  warn "loading $f";
  $self->pipeline->get_by_name('filesrc')->set(location => $f);

  my $file= '/dchha48_Prophets_of_Doom.mp3';
  my $path = $Bin . '/' . $file;
  $omnibin-> set(uri => Glib::filename_to_uri $path, "localhost");
}
sub play{
  my ($self) = @_;
  $self->pipeline->set_state('playing');
  $omnibin -> set_state("playing");
  warn 'PLAYING';
}

1;


