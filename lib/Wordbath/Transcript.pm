package Wordbath::Transcript;
use Moose;
use Modern::Perl;
use Wordbath::Transcript::AudioSync;
use Wordbath::Transcript::Model;

with 'Wordbath::Roles::Logger';

#sub DEBUG{}

#signal ('word-changed');
#signal ('word-entered-focus');
#signal ('word-left-focus');

# This is intended to serve as the controller for the document, and provide
# the scrolled text widget.
#
# Maybe this should've subclassed textview, but it's encompassed
# in a scrolled window, and it uses Moose.

has model => (
  isa => 'Wordbath::Transcript::Model',
  is => 'rw',
);

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
  my $buf = $wordbox->get_buffer;
  $self->model(Wordbath::Transcript::Model->new(buf => $buf));

  $wordbox->set_wrap_mode('word');
  $scrolled->add($wordbox);
  my $fontdesc = Pango::FontDescription->from_string('monospace 10');
  $wordbox->modify_font($fontdesc);
  $self->_text_widget($wordbox);

  $wordbox->signal_connect('move-cursor', \&_on_txt_move, $self);
  $wordbox->signal_connect('insert-at-cursor', \&_on_txt_insert, $self);
  $wordbox->signal_connect('delete-from-cursor', \&_on_txt_delete, $self);
  return $scrolled;
}

sub _on_txt_move{
  my ($txt,$step_size, $count, $extend_selection, $self) = @_;
}
sub _on_txt_insert{
  my ($txt,$string, $self) = @_;
  $self->logger->DEBUG("insertion event. txt: $string");
}
sub _on_txt_delete{
  my ($txt,$deltype, $count, $self) = @_;
  $self->logger->DEBUG("deletion event. deltype: $deltype, count: $count");
}

sub grab_focus{
  my $self = shift;
  $self->_text_widget->grab_focus();
}


sub scroll_to_end{
  my $self = shift;
  my $buf = $self->_buf;
  my $end = $buf->get_end_iter();
  $buf->place_cursor($end);
  my $textmark = $buf->get_insert;
  $self->_text_widget->scroll_mark_onscreen($textmark);
}


has _deferred_start => (
  is => 'rw',
);
has _deferred_end => (
  is => 'rw',
);





sub save_wbml{
  my ($self, $wbml_path) = @_;
  $self->model->save_wbml($wbml_path);
}

1;

