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

use Array::Compare;
# $data will be the first argument,
#  so the handler can be a method of whatever $data is.
has _signals => (
  is => 'ro',
  isa => 'HashRef',
  default => sub{{pos_change => [],}},
);
has _last_blurps =>(
  is => 'ro',
  isa => 'HashRef',
  default => sub{{}},
);
sub whenever {
  my ($self, $signal_name, $cb, $data) = @_;
  my $sigs = $self->_signals->{$signal_name};
  return unless $sigs;
  my $handler = {cb => $cb, data => $data};
  push @$sigs, $handler
}
sub blurp{
  my $self = shift;
  my $signal_name = shift;
  my $sigs = $self->_signals->{$signal_name};
  die "no such sig: $signal_name" unless $sigs;
  # @_ now contains signal-specific stuff,
  #  like cursor position or whatever.
  for my $handler (@$sigs){
    my $cb   = $handler->{cb};
    my $data = $handler->{data};
    $cb->($data, @_);
  }
  $self->_last_blurps->{$signal_name} = [@_];
}
# return number of signal handlers for a specific signal.
sub blurps{
  my ($self, $signal_name) = @_;
  my $sigs = $self->_signals->{$signal_name};
  return scalar @$sigs
}
#returns an arrayref. Or undef if this signal hasn't been blurped.
sub last_blurp{
  my ($self, $signal_name) = @_;
  return $self->_last_blurps->{$signal_name};
}
#takes a signal & arrayref.
sub last_blurp_matches{
  my ($self, $signal_name, $blurp) = @_;
  die "no such signal $signal_name"
     unless $self->blurps($signal_name);
  my $last_blurp = $self->last_blurp($signal_name);
  return 0 unless defined $last_blurp;
  my $comp = Array::Compare->new();
  return $comp->simple_compare ($blurp, $last_blurp);
}
sub _on_pos_change{
  my $self = shift;
  #use Array::Compare.
  return unless $self->blurps('pos_change');
  my ($line, $col) = $self->get_text_pos();

  #only blurp on changes. It's a change signal.
  return if $self->last_blurp_matches(pos_change => [$line,$col]);

  $self->blurp(pos_change => $line,$col);
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
  my $pos_ns = 12345;#$self->player->pos_ns;
  my $pa = {
    mark => $new_mark,
    pos_ns => $pos_ns,
    time_placed => time,
  };
  $self->_pseudo_anchor_push($pa);
}

has _slabels_to_try => (
  traits => ['Array'],
  isa => 'ArrayRef',
  is => 'rw',
  handles => {
    _untried_slabels => 'count',
    _next_untried_slabel => 'pop',
  },
);

has _last_tried_slabel => (
  isa => 'Str',
  is => 'rw',
);

sub collect_slabels{
  my $self = shift;
  my $txt = $self->current_text;
  # extract all labels from text.
  my @slabels;
  my $floating_spkr_lbl = qr|[^:\n]{1,40}|;
  push @slabels, $1 if $txt =~ m|^($floating_spkr_lbl):\s|;
  push @slabels, $1 while $txt =~ m|\n($floating_spkr_lbl):\s|g;
  if (@slabels >= 2){
    unshift @slabels, pop @slabels; #penultimate first..
  }
  unshift @slabels, 'Interviewer';
  unshift @slabels, 'Interviewee';
  my %seen;
  @slabels = reverse grep {not $seen{$_}++} reverse @slabels;
  $self->_slabels_to_try(\@slabels);
  say "collected labels: ".scalar @slabels;
}

sub next_slabel_in_text{
  my $self = shift;
  my $txt = $self->current_text;
  my $lst_lbl = $self->_last_tried_slabel;
  if ($lst_lbl and $txt =~ /\Q$lst_lbl\E:\s+$/){
    say 'replacing last speaker label.';
    my $buf = $self->_buf;
    my $iter = $buf->get_end_iter;
    my $end = $buf->get_end_iter;
    $iter->backward_chars (length $&);
    $buf->delete($iter,$end);
    $txt =~ s/\Q$lst_lbl\E:\s+$//;
    #replace last label with the next-best..
    $self->collect_slabels unless $self->_untried_slabels;
    my $next_lbl = $self->_next_untried_slabel;
    $self->_append_slabel($next_lbl);
  }
  else {
    say 'collecting speaker label';
    $self->_insert_pseudo_anchor_here_and_now();;
    $self->collect_slabels;
    my $next_lbl = $self->_next_untried_slabel;
    $self->_append_slabel($next_lbl);
  }
}

sub strip_ending_whitespace{
  my $self = shift;
  my $buf = $self->_buf;
  for(1..10){  #strip some whitespace, char by char
    my $end = $buf->get_end_iter();
    my $pen = $buf->get_end_iter();
    $pen->backward_char;
    last if ($buf->get_text($pen,$end, 0) =~ /\S/);
    $buf->delete($pen, $end);
  }
}

sub _append_slabel{
  my ($self, $next_lbl) = @_;
  my $txt = $self->current_text;
  #return unless $next_lbl;
  say "appending speaker label $next_lbl";
  my $buf = $self->_buf;
  $self->strip_ending_whitespace();
  my $end = $buf->get_end_iter();

  my $append_text = "";
  $append_text .= "\n\n" if $end->copy->backward_char; #at the beginning?
  $append_text .= "$next_lbl: ";
  $buf->insert($end, $append_text);
  $self->scroll_to_end();
  $self->_last_tried_slabel($next_lbl);
}

sub scroll_to_end{
  my $self = shift;
  my $buf = $self->_buf;
  my $end = $buf->get_end_iter();
  $buf->place_cursor($end);
  my $textmark = $buf->get_insert;
  $self->_text_widget->scroll_mark_onscreen($textmark);
}

1;

