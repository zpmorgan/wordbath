package Wordbath::App;
use Moose;
use Modern::Perl;
use Gtk3 -init;
use FindBin '$Bin';
use Pango;
use File::Slurp;

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
has _txt_pos_lbl => (
  isa => 'Gtk3::Label',
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
has _audio_path => (
  isa => 'Str',
  is => 'rw',
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

    my $scrolled_text_stuff = Gtk3::ScrolledWindow->new();
    {
      $scrolled_text_stuff->set_vexpand(1);
      $scrolled_text_stuff->set_hexpand(0);
      my $wordbox = Gtk3::TextView->new();
      $wordbox->set_wrap_mode('word');
      $self->_text_widget($wordbox);
      my $fontdesc = Pango::FontDescription->from_string('monospace 10');
      $wordbox->modify_font($fontdesc);

      $wordbox->signal_connect('move-cursor', \&_on_txt_move, $self);
      $wordbox->signal_connect('insert-at-cursor', \&_on_txt_insert, $self);
      $wordbox->signal_connect('delete-from-cursor', \&_on_txt_delete, $self);
      $wordbox->get_buffer->signal_connect('mark-set', \&_on_buf_mark_set, $self);
      $wordbox->get_buffer->signal_connect('changed', \&_on_buf_changed, $self);

      $scrolled_text_stuff->add($wordbox);
    }

    my $ratbuttbar = Gtk3::Box->new('horizontal', 3);
    $self->_populate_ratbuttbar($ratbuttbar);

    $win->add($vbox);
    $vbox->pack_start($menubar, 0,0,0);
    $vbox->pack_start($ratbuttbar, 0,0,0);
    $vbox->pack_start($seekbar, 0,0,0);
    $vbox->pack_start($scrolled_text_stuff, 1,1,0);
    Glib::Timeout->add( 300, \&update_clock, [$self, $clock]);
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
  $self->_text_widget->grab_focus();
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
  if($e->keyval == 32 && ($e->state * 'shift-mask')){
    DEBUG('TOGGLE');
    $self->player->toggle_play_state;
    return 1;
  }
  #shift+left. Backwards 1 sec
  if ($e->keyval == 65361 && ($e->state * 'shift-mask')){
    $self->player->shift_seconds(-2);
    return 1;
  }
  #shift+right. Forwards 1 sec
  if ($e->keyval == 65363 && ($e->state * 'shift-mask')){
    $self->player->shift_seconds(2);
    return 1;
  }
  # F5
  if ($e->keyval == 65474){
    $self->_next_speaker_label_in_text;
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

has _ratbutts => (is => 'rw', isa => 'ArrayRef', default => sub{[]});
has _cur_rate_lbl => (is => 'rw', isa => 'Gtk3::Label');
has _ratbuttbar => (is => 'rw', isa => 'Gtk3::Box');

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
  $self->_cur_rate_lbl(Gtk3::Label->new('foo'));
  $container->pack_start($self->_cur_rate_lbl, 0,0,0);
}

sub _ratbutt_clicked{
  my ($wodget,$data) = @_;
  my ($self,$rate) = @$data;
  $self->player->set_rate($rate);
  $self->_text_widget->grab_focus();
}

sub _adjust_rate {
  my ($self, $adj) = @_;
  my $prev_rate = $self->player->get_rate();
  my $next_rate = $prev_rate + $adj;
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

#misc callbacks. mark-set seems to be kind of a catch-all.
sub _on_txt_move{
  my ($txt,$step_size, $count, $extend_selection, $self) = @_;
  #$self->update_txt_pos_lbl;
}
sub _on_txt_insert{
  my ($txt,$string, $self) = @_;
  say "insertion event. txt: $string";
}
sub _on_txt_delete{
  my ($txt,$deltype, $count, $self) = @_;
  say "deletion event. deltype: $deltype, count: $count";
}
sub _on_buf_mark_set{
  my ($txt,$iter, $mark, $self) = @_;
  $self->update_txt_pos_lbl;
}
sub _on_buf_changed{
  my ($txt, $self) = @_;
  $self->update_txt_pos_lbl;
  my ($line, $col) = $self->get_text_pos();
  say "buf 'changed' event. Cursor: line $line, col $col";
}

sub _next_speaker_label_in_text{
  my $self = shift;
  # extract all labels from text.
  my $txt = $self->current_text;
  my $floating_spkr_lbl = qr|[^:\n]{1,40}|;
  my @labels;
  push @labels, $1 if $txt =~ m|^($floating_spkr_lbl):\s|;
  push @labels, $1 while $txt =~ m|\n($floating_spkr_lbl):\s|g;
  my $next_lbl = $labels[-2];
  #return unless $next_lbl;
  $next_lbl //= $labels[-1] eq 'Interviewer' ? 'Interviewee' : 'Interviewer';
  say "appending speaker label $next_lbl";
  my $buf = $self->_text_widget->get_buffer();
  for(1..10){  #strip some whitespace, char by char
    my $end = $buf->get_end_iter();
    my $pen = $buf->get_end_iter();
    say $buf->get_text($pen,$end, 0);
    $pen->backward_char;
    say $buf->get_text($pen,$end, 0);
    last if ($buf->get_text($pen,$end, 0) =~ /\S/);
    $buf->delete($pen, $end);
  }
  my $newline_padding = "\n\n";
  my $end = $buf->get_end_iter();
  $buf->insert($end, $newline_padding . $next_lbl . ': ');
  $end = $buf->get_end_iter();
  $buf->place_cursor($end);
  my $textmark = $buf->get_insert;
  $self->_text_widget->scroll_mark_onscreen($textmark);
}

sub get_text_pos{
  my $self = shift;
  my $txt = $self->_text_widget;
  my $buf = $txt->get_buffer;
  my $textmark = $buf->get_insert;
  my $textiter = $buf->get_iter_at_mark ($textmark);
  my $line = $textiter->get_line;
  my $col = $textiter->get_line_offset;
  return ($line, $col);
}


#called by callbacks on textview whenever text or cursor changes
sub update_txt_pos_lbl{
  my $self = shift;
  my $lbl = $self->_txt_pos_lbl;
  my ($line, $col) = $self->get_text_pos();
  my $pos_txt = "Ln: $line, Col: $col";
  $lbl->set_text($pos_txt);
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

sub current_text{
  my $self = shift;
  my $buf = $self->_text_widget->get_buffer();
  my ($start, $end) = $buf->get_bounds();
  $end->forward_char();
  my $txt = $buf->get_text($start, $end, 1);
  return $txt;
}
sub save_text{
  my $self = shift;
  my $file_path = $self->_text_file_path();
  my $txt = $self->current_text;
  #make sure there's a newline at the end?
  $txt .= "\n" unless $txt =~ m|\n$|;

  write_file($file_path, $txt);
  say "wrote to $file_path";
}
sub _text_file_path{
  my $self = shift;
  my $audio_path = $self->_audio_path;
  return $audio_path . '.txt';
}

1;


