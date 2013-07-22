package Wordbath::App;
use Moose;
use Gtk3 -init;
use FindBin '$Bin';

my $LOOP; # ?
$LOOP = Glib::MainLoop->new();

sub DEBUG{};

#gtk3 stuff.

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

has player => (
  isa => 'Wordbath::Player',
  is => 'ro',
  lazy => 1,
  builder => '_build_player',
);

sub _build_player{
  my $self = shift;
  return Wordbath::Player->new();
}

sub _build_win{
  my $self = shift;
  my $win = Gtk3::Window->new();
  $win->set_title('Wordbath');
  $win->set_border_width(0);
  $win->set_size_request(600,400);
  my $accel_group = Gtk3::AccelGroup->new;
  $win->add_accel_group($accel_group);
  $win->signal_connect (destroy => sub { 
      $self->player->shut_down();
      $LOOP->quit;
    });

  {
    my $vbox = Gtk3::Box->new('vertical', 3);
    my $menubar = Gtk3::MenuBar->new();
    my $menuitem = Gtk3::MenuItem->new_with_label('foo');
    my $clock = Gtk3::MenuItem->new_with_label('12:34');
    $menubar->append($menuitem);
    $menubar->append($clock);
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
    $button1->signal_connect('clicked', sub{
        my $text = $self->player->pos_ns();
        #$self->player->print_status();
        $button1->set_label( $text );
      });
    $button2->signal_connect('clicked', sub{
        $self->player->set_rate(.25);
      });
    Glib::Timeout->add( 40, \&update_clock, [$self, $clock]);
  }
  $win->show_all();
  return $win;
}

#called several times per second.
sub update_clock{
  my ($self, $clock) = @{shift()};
  my $clock_label = $clock->get_child;
  my $pos_ns = $self->player->pos_ns;
  my $dur_ns = $self->player->dur_ns;
  my $pos_sec = int ($pos_ns / 10**9);
  my $dur_sec = int ($dur_ns / 10**9);
  my $new_clock_text = "$pos_sec / $dur_sec";
  $clock_label->set_text($new_clock_text);
  $clock->show_all();
  return 1;
}

sub run{
  my $self = shift;
  $self->win;
  $LOOP->run();
  #Gtk3::main;
}

1;


