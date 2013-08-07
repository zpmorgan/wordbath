package Wordbath::Transcript;
use Moose;
use Modern::Perl;

#
# This is intended to serve as the model for the document, and provide
# the scrolled text widget.
#
# Maybe this should've subclassed textview, but it's encompassed
# in a scrolled window, and it uses Moose.

has scrolled_widget => (
  is => 'rw',
  isa => 'Object',
  builder => '_build_scrolled_widget',
);
has _text_widget => (
  is => 'rw',
  isa => 'Object',
);

sub _buf{
  my $self = shift;
  my $txt = $self->_text_widget;
  my $buf = $txt->get_buffer;
  return $buf;
}

sub _build_scrolled_widget{
  my $self = shift;
  my $scrolled = Gtk3::ScrolledWindow->new();
  $scrolled->set_vexpand(1);
  $scrolled->set_hexpand(0);
  my $wordbox = Gtk3::TextView->new();
  $wordbox->set_wrap_mode('word');
  $scrolled->add($wordbox);
  my $fontdesc = Pango::FontDescription->from_string('monospace 10');
  $wordbox->modify_font($fontdesc);
  $self->_text_widget($wordbox);

  $wordbox->signal_connect('move-cursor', \&_on_txt_move, $self);
  $wordbox->signal_connect('insert-at-cursor', \&_on_txt_insert, $self);
  $wordbox->signal_connect('delete-from-cursor', \&_on_txt_delete, $self);
  $wordbox->get_buffer->signal_connect('mark-set', \&_on_buf_mark_set, $self);
  $wordbox->get_buffer->signal_connect('changed', \&_on_buf_changed, $self);
  return $scrolled;
}

sub _buf{
  my $self = shift;
  my $txt = $self->_text_widget;
  my $buf = $txt->get_buffer;
  return $buf;
}

sub current_text{
  my $self = shift;
  my $buf = $self->_buf;
  my ($start, $end) = $buf->get_bounds();
  $end->forward_char();
  my $txt = $buf->get_text($start, $end, 1);
  return $txt;
}
sub grab_focus{
  my $self = shift;
  $self->_text_widget->grab_focus();
}

#misc callbacks. mark-set seems to be kind of a catch-all.
sub _on_txt_move{
  my ($txt,$step_size, $count, $extend_selection, $self) = @_;
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
  $self->_on_pos_change;
}
sub _on_buf_changed{
  my ($txt, $self) = @_;
  $self->_on_pos_change;
  my ($line, $col) = $self->get_text_pos();
  say "buf 'changed' event. Cursor: line $line, col $col";
}

has _signals => (
  is => 'rw',
  isa => 'HashRef',
  default => sub{{}},
);
sub _on_pos_change{
  my $self = shift;
  my $sig = $self->_signals->{pos_change};
  return unless $sig;
  my ($line, $col) = $self->get_text_pos();
  $sig->{cb}->($sig->{data}, $line, $col);
}
sub set_on_pos_change_cb{
  my ($self, $cb, $app) = @_;
  my ($line, $col) = $self->get_text_pos();
  $self->_signals->{pos_change} = {cb => $cb, data => $app};
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

# TODO: anchor stuff might belong in Wordbath::SpaceTime :)
has _pseuso_anchors => (
  is => 'rw',
  isa => 'ArrayRef',
  default => sub{[]},
  traits => ['Array'],
  handles => {
    _pseudo_anchor_push => 'push',
  },
);

sub _insert_pseudo_anchor_here_and_now{
  my $self = shift;
  my $buf = $self->_buf;
  #my $new_mark = $buf->get_insert->copy;
  my $iter = $buf->get_iter_at_mark($buf->get_insert);
  my $new_mark = $buf->create_mark('foo', $iter, 0);;
  my $pos_ns = $self->player->pos_ns;
  my $pa = {
    mark => $new_mark,
    pos_ns => $pos_ns,
    time_placed => time,
  };
  $self->_pseudo_anchor_push($pa);
}


1;

