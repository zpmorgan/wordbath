package Wordbath::App;
use Moose;
use Modern::Perl;
use Gtk3 -init;
use FindBin '$Bin';
use Pango;
use File::Slurp;
use lib 'lib';
use Math::Roundeth;
use Wordbath::Speller;
use Wordbath::Transcript;

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

has transcript => (
  isa => 'Wordbath::Transcript',
  is => 'rw',
  builder => '_build_tsv',
);
has _seekbar => (
  isa => 'Gtk3::Scale',
  is => 'rw',
);
has _txt_pos_lbl => (
  isa => 'Gtk3::Label',
  is => 'rw',
);

has _speller => (
  isa => 'Wordbath::Speller',
  is => 'ro',
  builder => '_build_speller',
);

has _slabeler_widget => (
  isa => 'Object',
  is => 'ro',
  builder => '_build_slabeler_widget',
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
has _audio_path => (
  isa => 'Str',
  is => 'rw',
);
has _accel_group => (
  is => 'rw',
  isa => 'Gtk3::AccelGroup',
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
  $self->_accel_group ($accel_group);
  $self->_do_hotkeys();

  $win->signal_connect (destroy => sub { 
      $self->please_quit();
    });
  $win->signal_connect('key-press-event', \&_win_key_press, $self);
  {
    my $vbox = Gtk3::Box->new('vertical', 3);
    my $menubar = Gtk3::MenuBar->new();
    my $file_menu = Gtk3::Menu->new();
    $file_menu->set_accel_group($accel_group);
    my $file_menuitem = Gtk3::MenuItem->new_with_label('File');
    $file_menuitem->set_submenu($file_menu);

    my $save_item = Gtk3::MenuItem->new_with_label('Save');
    {
      my ($keyval, $mask) = Gtk3::accelerator_parse('<Control>S');
      $save_item->add_accelerator('activate', $accel_group, $keyval, $mask, 'visible');
      $save_item->signal_connect(activate => sub{ $self->save_text });
    }
    my $quit_item = Gtk3::MenuItem->new_with_label('Quit');
    {
      my ($keyval, $mask) = Gtk3::accelerator_parse('<Control>Q');
      $quit_item->add_accelerator('activate', $accel_group, $keyval, $mask, 'visible');
      $quit_item->signal_connect(activate => sub{ $self->please_quit});
    }

    $file_menu->append($save_item);
    $file_menu->append($quit_item);

    my $clock = Gtk3::MenuItem->new_with_label('12:34');
    my $txt_pos = Gtk3::MenuItem->new_with_label('Ln:0  Col:0');
    $self->_txt_pos_lbl($txt_pos->get_child());
    $menubar->append($file_menuitem);
    $menubar->append($clock);
    $menubar->append($txt_pos);

    my $seekbar = Gtk3::Scale->new('horizontal', Gtk3::Adjustment->new(0,0,100,1,0,0));
    $seekbar->signal_connect('value-changed' => \&_seekbar_saught, $self);
    $seekbar->set_draw_value(0);
    $self->_seekbar($seekbar);

    $seekbar->signal_connect('button-press-event', \&_click_1_to_2);
    $seekbar->signal_connect('button-release-event', \&_click_1_to_2);

    my $ratbuttbar = Gtk3::Box->new('horizontal', 3);
    $self->_populate_ratbuttbar($ratbuttbar);

    $win->add($vbox);
    $vbox->pack_start($menubar, 0,0,0);
    $vbox->pack_start($ratbuttbar, 0,0,0);
    $vbox->pack_start($seekbar, 0,0,0);

    my $text_and_sidebar = Gtk3::Box->new('horizontal', 3);
    {
      my $transcript_widget = $self->transcript->scrolled_widget;
      my $sidebar = Gtk3::Box->new('vertical', 3);
      $sidebar->get_style_context->add_class("sidebar");
      $text_and_sidebar->pack_start($transcript_widget, 1,1,0);
      $text_and_sidebar->pack_start($sidebar, 0,0,0);
      $sidebar->pack_start($self->_speller->widget, 0,0,0);
      $sidebar->pack_start($self->_slabeler_widget, 0,0,0);
      #$_->get_style_context->remove_class("background")
      #  for ($sidebar, $self->_speller->widget, $self->_slabeler_widget);
      $self->_slabeler_widget->get_style_context->add_class("sidebar");
    }

    $vbox->pack_start($text_and_sidebar, 1,1,0);
    Glib::Timeout->add( 300, \&update_clock, [$self, $clock]);
  }

  $self->_load_styles();
  $win->show_all();
  return $win;
}

# Hotkey stuff.
my $_method_hotkeys = [
  ['shift-mask','space', \&play_pause],
  ['control-mask','t', \&seek_text_from_audio],
  ['control-mask','f', \&seek_audio_from_text],
  # gtk can't have arrow key accelerators?
  #['shift-mask','leftarrow', \&rel_seek, -2],
];
sub _do_hotkeys{
  my ($self) = @_;
  my $ag = $self->_accel_group;
  for my $hk (@$_method_hotkeys){
    my $keyval = Gtk3::Gdk::keyval_from_name($hk->[1]);
    $ag->connect ($keyval, $hk->[0], 'visible', sub{$hk->[2]->($self, $hk->[3])} );
  }
}

sub play_pause{
  my $self = shift;
  $self->player->toggle_play_state;
}
sub rel_seek{
  my ($self, $secs) = @_;
  $self->player->shift_seconds($secs);
}
sub seek_text_from_audio{
  my $self = shift;
  say 'TODO: Move text cursor.';
}
sub seek_audio_from_text{
  my $self = shift;
  say 'TODO: seek audio position.';
}


# css.
sub _load_styles{
  my $self = shift;
  my $p = Gtk3::CssProvider->new;
  my $css_filename = 'delorean-noir.css';
  # Says Perl: "What's a gfile?" How do I do this?
  # my $file = Gtk3::gfile_new_for_path($css_filename);
  # $p->load_from_file($css_filename);
  my $cssdata = read_file('delorean-noir.css');
  $p->load_from_data($cssdata, -1);
  my $d = Gtk3::Gdk::Display::get_default ();
  my $s = $d->get_default_screen;
  Gtk3::StyleContext::add_provider_for_screen (
    $s, $p, Gtk3::STYLE_PROVIDER_PRIORITY_USER);
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
  $self->transcript->grab_focus();
}
sub _click_1_to_2{
  my ($widget, $event) = @_;
  if( $event->button == 1){
    $event->button (2);
  }
  return 0;
}
sub _win_key_press{
  my ($w, $e, $self) = @_;
  DEBUG("state: ". $e->state .' ,  button: '. $e->keyval);
  #shift+left. Backwards 1 sec
  if ($e->keyval == 65361 && ($e->state * 'shift-mask')){
    $self->rel_seek(-2);
    return 1;
  }
  #shift+right. Forwards 1 sec
  if ($e->keyval == 65363 && ($e->state * 'shift-mask')){
    $self->rel_seek(2);
    return 1;
  }
  # F5
  if ($e->keyval == 65474){
    $self->transcript->next_slabel_in_text;
    return 1;
  }
  # F7
  if ($e->keyval == 65476){
    $self->_adjust_rate(-.03);
    return 1;
  }
  # F8
  if ($e->keyval == 65477){
    $self->_adjust_rate(+.03);
    return 1;
  }
  return 0;
}

### Audio rate adjustment stuff.
my @audio_rate_options = (
  .25,.35,.45,.55,.65,.75,.85,1,1.25,1.5,1.75,2
);

# rate buttons. feel free to rename if you come up with a better system.
has _ratbutts => (is => 'rw', isa => 'ArrayRef', default => sub{[]});
has _cur_rate_lbl => (is => 'rw', isa => 'Gtk3::Label');
has _ratbuttbar => (is => 'rw', isa => 'Gtk3::Box');

sub _find_ratbutt_for_rate{
  my ($self, $rate) = @_;
  my $i;
  for (0..$#audio_rate_options){
    $i = $_ if $rate == $audio_rate_options[$_];
  }
  return unless defined $i;
  return $self->_ratbutts->[$i];
}

sub _populate_ratbuttbar{
  my ($self, $container) = @_;
  $self->_ratbuttbar ($container);
  # click on these buttons to change audio speed.
  my @rate_buttons;
  for my $rate (@audio_rate_options){
    my $percent_text = ($rate*100) . '%';
    my $ratbutt = Gtk3::Button->new ($percent_text);
    $ratbutt->signal_connect ( clicked => \&_ratbutt_clicked, [$self,$rate]);
    push @rate_buttons, $ratbutt;
  }
  for (@rate_buttons){
    $container->pack_start($_,0,0,0);
  }
  $self->_ratbutts(\@rate_buttons);
  my $rate_lbl = Gtk3::Label->new('');
  $rate_lbl->get_style_context->add_class("rate-lbl");
  $self->_cur_rate_lbl($rate_lbl);
  $container->pack_start($rate_lbl, 0,0,0);
  my $rb = $self->_find_ratbutt_for_rate(1);
  $self->_choose_miscolorized_ratbutt($rb) if defined $rb;
}

has _miscolorized_ratbutt => (
  is => 'rw',
  isa => 'Gtk3::Button',
  clearer => '_lahdskajshflkg',
);
sub _clear_miscolorized_ratbutt{
  my ($self) = @_;
  my $rb = $self->_miscolorized_ratbutt;
  return unless $rb;
  $rb->get_style_context->restore;
  $self->_lahdskajshflkg();
  #why do I need these? shouldn't adding a class cause it to re-render?
  $rb->hide;
  $rb->show;
}
sub _choose_miscolorized_ratbutt{
  my ($self,$rb) = @_;
  $self->_clear_miscolorized_ratbutt if $self->_miscolorized_ratbutt;
  $rb->get_style_context->save;
  $rb->get_style_context->add_class("miscolorized");
  $self->_miscolorized_ratbutt($rb);
  $rb->hide;
  $rb->show;
  #$rb->queue_draw;
}

sub _ratbutt_clicked{
  my ($wodget,$data) = @_;
  my ($self,$rate) = @$data;
  $self->player->set_rate($rate);
  $self->transcript->grab_focus();
  $self->_cur_rate_lbl->set_visible(0);
  $self->_choose_miscolorized_ratbutt($wodget);
}

sub _adjust_rate {
  my ($self, $adj) = @_;
  my $prev_rate = $self->player->get_rate();
  my $next_rate = $prev_rate + $adj;
  $next_rate = nearest (.01, $next_rate);
  return if $next_rate < .03;
  $self->player->set_rate($next_rate);
  $self->_cur_rate_lbl->set_text(($next_rate * 100) . '%');
  #move the label around
  my $pos = 0;
  say "rate adjustment. next_rate: $next_rate";
  for my $opt (0 .. $#audio_rate_options){
    $pos = $opt;
    last if $audio_rate_options[$opt] > $next_rate;
    if ($audio_rate_options[$opt] == $next_rate){
      # same frequency as a button.
      $pos = -1;
      last;
    }
  }
  if ($pos >= 0){
    $self->_ratbuttbar->reorder_child($self->_cur_rate_lbl, $pos);
    $self->_cur_rate_lbl->set_visible(1);
  } else {
    $self->_cur_rate_lbl->set_visible(0);
  }
  $self->_clear_miscolorized_ratbutt();
  my $rb = $self->_find_ratbutt_for_rate($next_rate);
  $self->_choose_miscolorized_ratbutt($rb) if defined $rb;
}


#called several times per second. TODO: once every audio second?
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

sub _build_tsv{
  my $self = shift;
  my $transcript = Wordbath::Transcript->new();
  $transcript->whenever(pos_change => \&update_txt_pos_lbl, $self);
  return $transcript;
}

#called by callbacks on textview whenever text or cursor changes
sub update_txt_pos_lbl{
  my ($self,$line,$col) = @_;
  my $lbl = $self->_txt_pos_lbl;
  my $pos_txt = "Ln: $line, Col: $col";
  $lbl->set_text($pos_txt);
}

sub _build_speller{
  my $self = shift;
  my $speller = Wordbath::Speller->new();
  $speller->check_all_button->signal_connect (
    clicked => sub{$self->transcript->spellcheck_all}
  );
  return $speller;
}

sub _build_slabeler_widget{
  my $self = shift;
  return Gtk3::Label->new('SLABELER');
}


sub run{
  my $self = shift;
  $self->win;
  $LOOP->run();
  #Gtk3::main;
}

sub load_audio_file{
  my ($self, $file) = @_;
  $self->_audio_path($file);
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

sub please_quit{
  my $self = shift;
  $self->player->shut_down();
  $LOOP->quit;
  say 'good bye.';
}

sub save_text{
  my $self = shift;
  my $file_path = $self->_text_file_path();
  my $txt = $self->transcript->current_text;
  #make sure there's a newline at the end?
  $txt .= "\n" unless $txt =~ m|\n$|;

  write_file($file_path, {binmode => ':utf8'}, $txt);
  say "wrote to $file_path";
}
sub _text_file_path{
  my $self = shift;
  my $audio_path = $self->_audio_path;
  return $audio_path . '.txt';
}

1;


