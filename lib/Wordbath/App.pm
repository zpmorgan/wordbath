package Wordbath::App;
use Moose;
use Gtk3 -init;
use FindBin '$Bin';
use Pango;

my @audio_rate_options = (
  .25,.35,.45,.55,.65,.75,.85,1,1.25,1.5,1.75,2
);

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
has _seekbar => (
  isa => 'Gtk3::Scale',
  is => 'rw',
);

has _natural_seekbar_value => (
  isa => 'Num',
  is => 'rw',
  default => 0,
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

    my $seekbar = Gtk3::Scale->new('horizontal', Gtk3::Adjustment->new(0,0,100,1,0,0));
    $seekbar->signal_connect('value-changed' => \&_seekbar_saught, $self);
    $seekbar->set_draw_value(0);
    $self->_seekbar($seekbar);

    $seekbar->signal_connect('button-press-event', \&_click_1_to_2);
    $seekbar->signal_connect('button-release-event', \&_click_1_to_2);

    my $scrolled_text_stuff = Gtk3::ScrolledWindow->new();
    {
      $scrolled_text_stuff->set_vexpand(1);
      $scrolled_text_stuff->set_hexpand(0);
      my $wordbox = Gtk3::TextView->new();
      $wordbox->set_wrap_mode('word');
      $self->_text_widget($wordbox);
      my $fontdesc = Pango::FontDescription->from_string('monospace 10');
      $wordbox->modify_font($fontdesc);

      $scrolled_text_stuff->add($wordbox);
    }

    # click on these buttons to change audio speed.
    my @rate_buttons;
    for my $rate (@audio_rate_options){
      my $percent_text = ($rate*100) . '%';
      my $ratbutt = Gtk3::Button->new ($percent_text);
      $ratbutt->signal_connect ( clicked => sub{
          $self->player->set_rate($rate);
        });
      push @rate_buttons, $ratbutt;
    }
    my $ratbuttbar = Gtk3::Box->new('horizontal', 3);
    for (@rate_buttons){
      $ratbuttbar->pack_start($_,0,0,0);
    }

    $win->add($vbox);
    $vbox->pack_start($menubar, 0,0,0);
    $vbox->pack_start($ratbuttbar, 0,0,0);
    $vbox->pack_start($seekbar, 0,0,0);
    $vbox->pack_start($scrolled_text_stuff, 1,1,0);
    Glib::Timeout->add( 40, \&update_clock, [$self, $clock]);
  }
  $win->show_all();
  return $win;
}

# example: 3700 -> "01:01:40"
sub _fmt_time_sec{
  my $tot_sec = int shift;
  my $sec = $tot_sec % 60;
  my $time_txt = sprintf ("%02d", $sec);
  my $min = int($tot_sec/60) % 60;
  $time_txt = sprintf("%02d:$time_txt", $min);

  #display hours?
  if ($tot_sec >= 3600){
    my $hr = int($tot_sec / 3600);
    $time_txt = sprintf("%02d:$time_txt", $hr);
  }
  return $time_txt;
}

sub _seekbar_saught{
  my ($widget, $self) = @_;
  my $sb = $self->_seekbar;
  my $value = $sb->get_value;
  return if ($value == $self->_natural_seekbar_value);
  $self->_natural_seekbar_value($value);
  $self->player->seek_sec($value);
}
sub _click_1_to_2{
  my ($widget, $event) = @_;
  if( $event->button == 1){
    $event->button (2);
  }
  return 0;
}

#called several times per second.
sub update_clock{
  my ($self, $clock) = @{shift()};
  my $clock_label = $clock->get_child;
  my $pos_ns = $self->player->pos_ns;
  my $dur_ns = $self->player->dur_ns;
  my $pos_sec = int ($pos_ns / 10**9);
  my $dur_sec = int ($dur_ns / 10**9);
  my $new_clock_text = _fmt_time_sec($pos_sec) .' / '. _fmt_time_sec($dur_sec);
  $clock_label->set_text($new_clock_text);

  #seekbar update position.
  $self->_natural_seekbar_value($pos_sec);
  $self->_seekbar->set_value($pos_sec);

  return 1;
}

sub run{
  my $self = shift;
  $self->win;
  $LOOP->run();
  #Gtk3::main;
}

sub load_audio_file{
  my ($self, $file) = @_;
  $self->win; #generate widgets, if they don't exist yet.
  $self->player->_load_audio_file($file);
  $self->player->set_rate(1);
  my $dur_sec = $self->player->dur_ns / 10**9;
  $self->_natural_seekbar_value(0);
  $self->_seekbar->set_range( 0, int $dur_sec );
  $self->_seekbar->set_value( 0 );
}

sub play{
  my $self = shift;
  $self->player->play();
}

1;


