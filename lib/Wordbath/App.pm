package Wordbath::App;
use Moose;
use Modern::Perl;
use utf8;
use Gtk3 -init;
use FindBin '$Bin';
use Pango;
use File::Slurp;
use lib 'lib';
use Wordbath::Util;
use Wordbath::Speller;
use Wordbath::Transcript;
use Wordbath::Config;

with 'Wordbath::Roles::Logger';

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
  builder => '_build_transcript',
  lazy => 1,
);

has config => (
  is => 'ro',
  isa => 'Wordbath::Config',
  default => sub{Wordbath::Config->load_or_create()},
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
  $win->signal_connect_swapped ('key-press-event', \&_win_key_press, $self);
  $win->signal_connect_swapped ('key-release-event', \&_win_key_release, $self);
  {
    my $vbox = Gtk3::Box->new('vertical', 3);
    my $menubar = Gtk3::MenuBar->new();
    my $file_menu = Gtk3::Menu->new();
    $file_menu->set_accel_group($accel_group);
    my $file_menuitem = Gtk3::MenuItem->new_with_label('File');
    $file_menuitem->set_submenu($file_menu);

    my @file_clickables = (
      [Save => '<Control>S', sub{$self->save_all}],
      ['Edit config' => undef, sub{ $self->config->launch_edit_window}],
      [Undo => '<Control>Z', sub{ $self->transcript->undo}],
      [Redo => '<Control>Y', sub{ $self->transcript->redo}],
      ['Keyboard Infodump' => undef, sub{ say $self->_arbitkeys->infodump}],
      [Quit => '<Control>Q', sub{$self->please_quit}],
    );
    for (@file_clickables){
      my $item = Gtk3::MenuItem->new_with_label($_->[0]);
      if (defined $_->[1]){
        my ($keyval, $mask) = Gtk3::accelerator_parse($_->[1]);
        $item->add_accelerator('activate', $accel_group, $keyval, $mask, 'visible');
      }
      $item->signal_connect(activate => $_->[2]);
      $file_menu->append($item);
    }


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
      $sidebar->pack_start($self->_speller->widget, 1,1,0);
      $sidebar->pack_start($self->_slabeler_widget, 1,1,0);
      #$_->get_style_context->remove_class("background")
      #  for ($sidebar, $self->_speller->widget, $self->_slabeler_widget);
      $self->_slabeler_widget->get_style_context->add_class("sidebar");
    }

    $vbox->pack_start($text_and_sidebar, 1,1,0);
    my $i = Glib::Timeout->add( 300, \&update_clock, [$self, $clock]);
    $self->_timeout_i($i);
  }

  $self->_load_styles();
  $win->show_all();
  return $win;
}

has _timeout_i => (is => 'rw', isa => 'Int');

sub play_pause{
  my $self = shift;
  my $new_state = $self->player->toggle_play_state;
  my $pa_type = $new_state eq 'playing' ? 'go' : 'stop';
  $self->transcript->insert_sync_vector_here_at_pos(type => $pa_type);
}
sub rel_seek{
  my ($self, $secs) = @_;
  $self->player->shift_seconds($secs);
}


# css.
sub _load_styles{
  my $self = shift;
  my $p = Gtk3::CssProvider->new;
  my $css_filename = 'delorean-noir.css';
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

# gtk scale bars only adjust from button2 clicks.
# This changes the event button and has it continue to propagate.
sub _click_1_to_2{
  my ($widget, $event) = @_;
  if( $event->button == 1){
    $event->button (2);
  }
  return 0;
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

use Wordbath::App::ArbitKeys;
has _arbitkeys => (
  is => 'ro',
  isa => 'Wordbath::App::ArbitKeys',
  lazy => 1,
  builder => '_build_arbitkeys',
);
my @arbitseeks = (
  ['<shift>left', -2],
  ['<shift>right', 2],
  ['<s>k', -1],
  ['<s>l', 1],
  ['<s>j', -4],
  ['<s>;', 4],
);
sub _build_arbitkeys{
  my $self = shift;
  my $keys = Wordbath::App::ArbitKeys->new();
  for my $foo (@arbitseeks){
    $keys->handle( keycombo => $foo->[0], cb => sub{$self->rel_seek($foo->[1])} );
  }
  $keys->handle( keycombo => 'F5', cb => sub{ 
      $self->transcript->next_slabel_in_text(pos_ns => $self->player->pos_ns);
      return 1});
  $keys->handle( keycombo => 'F7', cb => sub{ $self->_adjust_rate(-.03); return 1});
  $keys->handle( keycombo => 'F8', cb => sub{ $self->_adjust_rate(+.03); return 1});
  $keys->handle( keycombo => '<a>space', cb => sub{ $self->play_pause; return 1});
  $keys->whenever(retraction => sub{ shift;$self->transcript->arbitrary_text_retraction(@_) }, $self);
  # <t>ext (s)eek-sync to audio pos
  $keys->handle( keycombo => '<t>s', cb => sub{
      $self->transcript->sync_text_to_pos_ns( $self->player->pos_ns) ; return 1});
  $keys->handle( keycombo => '<a>s', cb => sub{
      my $pos_ns = $self->transcript->audio_pos_ns_at_cursor;
      $self->player->seek_ns($pos_ns);
      return 1;
    });

  return $keys;
}

sub _win_key_release{
  my ($self, $e, $w) = @_;
  my $arbit_res = $self->_arbitkeys->do_release_event($e);
}
sub _win_key_press{
  my ($self, $e, $w) = @_;
  $self->logger->DEBUG("state: ". $e->state .' ,  button: '. $e->keyval);
  my $arbit_res = $self->_arbitkeys->do_press_event($e);
  return 1 if $arbit_res;
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
  $next_rate = Wordbath::Util::round_nearest (.01, $next_rate);
  return if $next_rate < .03;
  $self->player->set_rate($next_rate);
  $self->_cur_rate_lbl->set_text(($next_rate * 100) . '%');
  #move the label around
  my $pos = 0;
  $self->logger->INFO("rate adjustment. next_rate: $next_rate");
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
  $self->known_duration_ns( $dur_ns);
  my $pos_sec = int ($pos_ns / 10**9);
  my $dur_sec = int ($dur_ns / 10**9);
  my $new_clock_text = _fmt_time_sec($pos_sec) .' / '. _fmt_time_sec($dur_sec);
  $clock_label->set_text($new_clock_text);

  #seekbar update position.
  $self->_natural_seekbar_value($pos_sec);
  $self->_seekbar->set_value($pos_sec);

  return 1;
}

sub _build_transcript{
  my $self = shift;
  my $transcript = Wordbath::Transcript->new();
  $transcript->audiosync->player($self->player);
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
  #my $speller = Wordbath::Speller->new();
  my $speller = $self->transcript->speller;
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

has known_duration_ns => (
  is => 'rw', isa=>'Int', trigger => sub{
    my ($self, $dur_ns, $old) = @_;
    return if !$dur_ns or $old;
    $self->logger->INFO("setting seekbar dur to $dur_ns / billion.");
    $self->_natural_seekbar_value(0);
    $self->_seekbar->set_range( 0, int ($dur_ns / 10**9));
    $self->_seekbar->set_value( 0 );
  });

sub load_audio_file{
  my ($self, $file) = @_;
  $self->_audio_path($file);
  $self->win; #generate widgets, if they don't exist yet.

  $self->player->_load_audio_file($file);
  $self->player->set_rate(1);
  $self->known_duration_ns( $self->player->dur_ns);
}

sub play{
  my $self = shift;
  $self->player->play();
}

sub please_quit{
  my $self = shift;
  $self->player->shut_down();
  $LOOP->quit;
  Glib::Source->remove($self->_timeout_i);
  $self->logger->NOTICE('good bye.');
}

sub save_all{
  my $self = shift;
  $self->save_text();
  $self->save_data();
}
use JSON;
sub save_data{
  my $self = shift;
  my $file_path = $self->_data_file_path();
  my $json = encode_json ($self->transcript->audiosync->to_hash);
  write_file($file_path, {binmode => ':utf8'}, $json);
  $self->logger->NOTICE("wrote sync vectors to $file_path");
  say("wrote sync vectors to $file_path");
}

sub save_text{
  my $self = shift;
  my $file_path = $self->_text_file_path();
  my $txt = $self->transcript->current_text;
  #make sure there's a newline at the end?
  $txt .= "\n" unless $txt =~ m|\n$|;

  write_file($file_path, {binmode => ':utf8'}, $txt);
  $self->logger->NOTICE("wrote to $file_path");
  say("wrote to $file_path");
}
sub _text_file_path{
  my $self = shift;
  my $audio_path = $self->_audio_path;
  return $audio_path . '.txt';
}
sub _data_file_path{
  my $self = shift;
  my $audio_path = $self->_audio_path;
  return $audio_path . '.wb';
}

sub log_to_file{
  my ($self, $path) = @_;
  open (my $fh, ">$path");
  $self->logger->config({fh => $fh});
  $self->logger->config({prefix => '%P::%F|%L%_'});
  $self->logger->NOTICE("logging to $path");
}
1;


