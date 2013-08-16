package Wordbath::Transcript;
use Moose;
use Modern::Perl;

with 'Wordbath::Whenever';
Wordbath::Whenever->import();;
signal ('pos_change');

#signal ('word-changed');
#signal ('word-entered-focus');
#signal ('word-left-focus');

# This is intended to serve as the model for the document, and provide
# the scrolled text widget.
#
# Maybe this should've subclassed textview, but it's encompassed
# in a scrolled window, and it uses Moose.
# Maybe the view & model should be separated next

has scrolled_widget => (
  is => 'rw',
  isa => 'Object',
  builder => '_build_scrolled_widget',
);
has _text_widget => (
  is => 'rw',
  isa => 'Object',
);

has _misspelled_word_tag => (
  is => 'rw',
  isa => 'Gtk3::TextTag',
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

  my $misspelled_word_tag = $wordbox->get_buffer->create_tag('missp');
  $misspelled_word_tag->set("underline-set" => 1);
  $misspelled_word_tag->set("underline" => 'error');
  $self->_misspelled_word_tag( $misspelled_word_tag );

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
  $wordbox->get_buffer->signal_connect_swapped('delete-range', \&on_delete_range, $self);
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
sub on_delete_range{
  my ($self, $start,$end, $buf) = @_;
  return if $self->undo_suppressed;

  my $txt = $buf->get_text($start,$end, 1);
  my $s = $buf->create_mark(undef, $start, 1);
  my $e = $buf->create_mark(undef, $start, 0);
  my $undo_sub = sub{$buf->delete($s,$e)};
  my $redo_sub = sub{$buf->insert($s,$txt)};
  $self->dodo(undo_sub => $undo_sub, redo_sub => $redo_sub);
}

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

sub _on_pos_change{
  my $self = shift;
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

has speller=> (
  is => 'ro',
  isa => 'Wordbath::Speller',
  builder => '_build_speller',
  lazy => 1,
);
sub _build_speller{
  my $self = shift;
  my $sc = Wordbath::Speller->new();
  #$sc->whenever('sp-replace-one' => \&spell_replace_all_words, $self);
  #$sc->whenever('sp-replace-all' => \&spell_replace_one_word, $self);
};

has _deferred_start => (
  is => 'rw',
);
has _deferred_end => (
  is => 'rw',
);



{
  package Wordbath::Transcript::Word;
  use Moose;

  has word => (isa => 'Str', is => 'ro', required => 1);
  has [qw|start end|] => (isa => 'Gtk3::TextIter', is => 'ro', required => 1);
  has [qw|_start_mark _end_mark|] => (isa => 'Gtk3::TextMark', is => 'rw');
  has _stable => (isa => 'Bool', is => 'rw', default => 0);
  has buf => (isa => 'Gtk3::TextBuffer', is => 'ro', builder => 'b_buf', lazy=>1);

  sub b_buf{
    my $self = shift;
    if ($self->is_stable){
      return $self->_end_mark->get_buffer;
    } else {
      return $self->start->get_buffer;
    }
  }
  sub is_stable{
    my $self = shift;
    my $res = $self->_stable;
    return $res
  }
  sub make_stable{
    my $self = shift;
    return if $self->is_stable;
    my $smark = $self->buf->create_mark ('sw'.rand, $self->start, 1);
    my $emark = $self->buf->create_mark ('ew'.rand, $self->end, 1);
    $self->_start_mark($smark);
    $self->_end_mark($emark);
    $self->_stable(1);
  }
  sub start_iter{
    my $self = shift;
    if (!$self->is_stable){
      return $self->start;
    }
    return $self->buf->get_iter_at_mark($self->start_mark);
  }
  sub end_iter{
    my $self = shift;
    if (!$self->is_stable){
      return $self->end;
    }
    return $self->buf->get_iter_at_mark($self->end_mark);
  }
  sub start_mark{
    my $self = shift;
    unless ($self->is_stable){
      warn 'getting mark from unstable word';
      $self->make_stable;
    }
    $self->_end_mark;
  }
  sub end_mark{
    my $self = shift;
    unless ($self->is_stable){
      warn 'getting mark from unstable word';
      $self->make_stable;
    }
    $self->_start_mark;
  }
  sub tag_missp{
    my $self = shift;
    my $buf = $self->buf;
    $self->buf->apply_tag_by_name('missp', $self->start_iter,$self->end_iter);
  }
  sub untag{
    my $self = shift;
    my $buf = $self->buf;
    my $s = $self->start_iter;
    my $e = $self->end_iter;
    # are these backwards?
    #say 'UNTAGGING' . $self .','. $self->start_iter->get_offset .','. $e->get_offset;
    $self->buf->remove_all_tags($s, $e);
  }

  use Text::Hunspell;
  my $speller = Text::Hunspell->new(
    "/usr/share/hunspell/en_US.aff",    # Hunspell affix file
    "/usr/share/hunspell/en_US.dic"     # Hunspell dictionary file
  );

  has _cached_spellings => (
    is => 'ro',
    isa => 'HashRef',
    default => sub{{}},
  );

  sub check_spelling{
    my $self = shift;
    my $txt = $self->word;
    my $cached = $self->_cached_spellings->{$txt};
    return $cached if $cached;
    $txt =~ s/^'//;
    $txt =~ s/'$//;
    if ($txt =~ /\s/){
      die "please dont check spelling of a word with space in it. ($txt)";
    }
    my $res;
    if ($speller->check($txt)){
      $res = 1;
    } else {
      $res = [ $speller->suggest($txt) ];
    }
    $self->_cached_spellings->{$txt} = $res;
    return $res;
  }
}

# misspelled word instances: [word, marked start, marked end]
# keyed by the actual spelling of the word.
has _misspelled_words => (
  isa => 'HashRef',
  is => 'ro',
  default => sub{{}},
);
sub add_misspelled_word{
  my ($self, $word) = @_;
  $word->make_stable;
  push @{$self->_misspelled_words->{$word->word}}, $word; #lol
}
sub remove_misspelled_word{
  my ($self, $word) = @_;
  $word->untag;
  $word->tag_missp;
  $word->untag;
  my @txt_instances = @{$self->_misspelled_words->{$word->word}};
  @txt_instances = grep {$_ != $word} @txt_instances;
  if (@txt_instances == 0){
    delete $self->_misspelled_words->{$word->word};
  } else {
    $self->_misspelled_words->{$word->word} = \@txt_instances;
  }
}
sub all_misspelled_words{
  my $self = shift;
  my @lists = values %{$self->_misspelled_words};
  # flatten.
  my @res;
  push @res, @$_ for @lists;
  return @res;
}

# these should be what hunspell doesn't break on.
my $word_chars= qr/\p{Alpha}|\d|'/;

# There's some duplication here. I declare it okay.
sub _at_word_begin{
  my ($buf,$iter) = @_;
  my $prevc = $iter->copy;
  $prevc->backward_char;
  my $char = $buf->get_text($prevc, $iter, 1);
  return 0 if ($char =~ $word_chars); #false if word char to left, 
  my $nextc = $iter->copy;
  $nextc->forward_char;
  $char = $buf->get_text($iter, $nextc, 1);
  return 0 if ($char !~ $word_chars); #false if not word char to right.
  return 1;
}
sub _at_word_end{
  my ($buf,$iter) = @_;
  my $prevc = $iter->copy;
  $prevc->backward_char;
  my $char = $buf->get_text($prevc, $iter, 1);
  return 0 if ($char !~ $word_chars); #false if space to left.
  my $nextc = $iter->copy;
  $nextc->forward_char;
  $char = $buf->get_text($iter,$nextc, 1);
  return 1 if $char eq '';
  return 0 if ($char =~ $word_chars); #false if character to right.
  return 1;
}
sub _inside_word{
  my ($buf,$iter) = @_;
  my $prevc = $iter->copy;
  $prevc->backward_char;
  my $char = $buf->get_text($prevc, $iter, 1);
  return 0 unless ($char =~ $word_chars);
  my $nextc = $iter->copy;
  $nextc->forward_char;
  $char = $buf->get_text($iter, $nextc, 1);
  return 0 unless ($char =~ $word_chars);
  return 1;
}

sub _b_to_word_begin{
  my ($buf,$iter) = @_;
  $iter->backward_char;
  while(!_at_word_begin($buf,$iter)){
    $iter->backward_char;
    return 0 if $iter->equal($buf->get_start_iter());
  }
  return 1
}
# return true if there's anoter word, false otherwise.
sub _f_to_word_begin{
  my ($buf,$iter) = @_;
  $iter->forward_char;
  while(!_at_word_begin($buf,$iter)){
    $iter->forward_char;
    return 0 if $iter->equal($buf->get_end_iter());
  }
  return 1
}
sub _f_to_word_end{
  my ($buf,$iter) = @_;
  $iter->forward_char;
  while(!_at_word_end($buf,$iter)){
    $iter->forward_char;
  }
}

sub _ranges_overlap{
  my ($s1,$e1,$s2,$e2) = @_;
  return 0 if $s1->compare($e2) == 1;
  return 0 if $s2->compare($e1) == 1;
  return 1;
}

sub spellcheck_range {
  my ($self, $range_start, $range_end) = @_;
  # expand range to encompass words partially overlapping range.
  my $buf = $self->_buf;
  my $start = $range_start->copy;
  #my $end= $range_end->copy;
  if (!_at_word_begin($buf,$start)){
    if (_inside_word($buf,$start)){
      _b_to_word_begin($buf,$start);
    } else { #between 2 non-word characters.
      _f_to_word_begin($buf,$start);
    }
  }
  #if (!_inside_word($buf,$end)){
  #  _f_to_word_end($buf,$end);
  #}
  #check each word.
  while(1){
    if (!_at_word_begin($buf,$start)){
      last unless _f_to_word_begin($buf,$start);
    }
    my $w_end = $start->copy;
    _f_to_word_end($buf,$w_end);
    last unless _ranges_overlap($start,$w_end, $range_start,$range_end);
    my $word_txt = $buf->get_text($start,$w_end,1);
    #warn $word_txt;
    #die if $word_txt eq ' ';
    my $word = Wordbath::Transcript::Word->new(
      word => $word_txt,
      start => $start->copy,
      end => $w_end->copy,
    );
    $self->_check_word_spelling($word);
    $start = $w_end;
  }
}
sub spellcheck_all{
  my $self = shift;
  #reset the misspelled word widget
  $self->speller->clear_missps; 
  #remove those little red underlines:
  my @missp_words = $self->all_misspelled_words;
  $self->remove_misspelled_word($_) for @missp_words;

  my ($start, $end) = $self->_buf->get_bounds();
  $self->spellcheck_range($start,$end);
}

sub _check_word_spelling{
  my ($self, $word) = @_;
  # ugh. sometimes apostrophes should be checked,
  # but not if it's at the beginning or end.
  my $res = $word->check_spelling;
  if (ref $res){
    $self->add_misspelled_word($word);
    #say "Word: $word_txt. suggs: @$res.";
    $self->speller->add_missp($word, $res);
    #mark the misspelled word.
    $word->tag_missp;
  }
}
sub spell_replace_all_words{
  my ($self, $incorrect, $correct, $instances) = @_;
}
sub spell_replace_one_word{
  my ($self, $incorrect, $correct, $start,$end) = @_;
}


#### UNDO / REDO
{
  package Wordbath::Transcript::DoDo;
  use Moose;
  use Modern::Perl;

  # has undo_sub, redo_sub
  for (qw/undo redo/){
    has $_ . '_sub' => (
      isa => 'CodeRef',
      is => 'ro',
      traits  => ['Code'],
      handles => {
        $_ => 'execute', #suppress undo detection first!
      },
    );
  }
}

# $transcript->dodo( undo_sub => sub{...}, redo_sub => sub{...} );
sub dodo{
  my $self = shift;
  my $dodo = Wordbath::Transcript::DoDo->new(@_);
  $self->push_undo($dodo);
  $self->clear_redo;
  if($self->count_undo > 100){
    $self->shift_undo;
    say 'forgetting oldest undo.'
  }
  say 'undoable op captured.'
}

# _undo_stack, _redo_stack.
# $self->pop_redo, $self->push_undo
for (qw/undo redo/){
  has "_$_"."_stack" => (
    isa => 'ArrayRef',
    is => 'rw',
    default => sub{[]},
    traits => ['Array'],
    handles => {
      #pop_undo, pop_redo, push_undo,push_redo, has_undo,has_redo
      "push_$_" => 'push',
      "shift_$_" => 'push', #maybe shift_undo a few times when the undo stack gets large.
      "pop_$_" => 'pop',
      "has_$_" => 'count',
      "count_$_" => 'count',
      "get_$_" => 'get', # get_undo(-1) for top of undo stack.
      "clear_$_" => 'clear', # empty the stack
    },
  );
}

has _undo_suppressed => (
  is => 'rw',
  isa => 'Bool',
  default => 0,
  traits => ['Bool'],
  handles => {
    suppress_dodo => 'set',
    unsuppress_dodo => 'unset',
  },
  reader => 'undo_suppressed',
);

sub undo {
  my $self = shift;
  return unless $self->has_undo;
  my $undo = $self->pop_undo;
  $self->suppress_dodo;
  eval{
    $undo->undo();
  };
  $self->unsuppress_dodo;
  $self->push_redo;
}
sub redo {
  my $self = shift;
  return unless $self->has_redo;
  my $redo = $self->pop_redo;
  $self->suppress_dodo;
  eval{
    $redo->redo();
  };
  $self->unsuppress_dodo;
  $self->push_undo;
}


1;

