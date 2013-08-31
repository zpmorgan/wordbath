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

#misc callbacks. mark-set seems to be kind of a catch-all.
sub on_delete_range{
  my ($self, $start,$end, $buf) = @_;
  return if $self->undo_suppressed;

  my $txt = $buf->get_text($start,$end, 1);
  my $s = $buf->create_mark(undef, $start, 1);
  my $e = $buf->create_mark(undef, $start, 0);
  my $undo_sub = sub{
    my $i = $buf->get_iter_at_mark($s);
    $buf->insert($i,$txt)
  };
  my $redo_sub = sub{
    my @i = map {$buf->get_iter_at_mark($_)} ($s,$e);
    $buf->delete(@i)
  };
  $self->dodo(undo_sub => $undo_sub, redo_sub => $redo_sub);
}



sub scroll_to_end{
  my $self = shift;
  my $buf = $self->_buf;
  my $end = $buf->get_end_iter();
  $buf->place_cursor($end);
  my $textmark = $buf->get_insert;
  $self->_text_widget->scroll_mark_onscreen($textmark);
}

has speller=> (
  is => 'ro',
  isa => 'Wordbath::Speller',
  builder => '_build_speller',
  lazy => 1,
);
sub _build_speller{
  my $self = shift;
  my $sc = Wordbath::Speller->new();
  $sc->whenever (ignoring => \&on_ignoring_missp, $self);
  return $sc;
  #$sc->whenever('sp-replace-one' => \&spell_replace_all_words, $self);
  #$sc->whenever('sp-replace-all' => \&spell_replace_one_word, $self);
};

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

