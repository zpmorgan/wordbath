package Wordbath::Transcript::Model;
use Moose;
use utf8;
use Modern::Perl;
use Wordbath::Transcript::AudioSync;

with 'Wordbath::Roles::Logger';
with 'Wordbath::Roles::Whenever';
Wordbath::Roles::Whenever->import();;
signal ('pos_change');
signal ('end_activity');

use XML::LibXML ':all';

# arg for constructor.
has from_wbml => (
  isa => 'Str',
  is => 'ro',
);

has buf => (
  is => 'ro',
  isa => 'Gtk3::TextBuffer',
  lazy => 1,
  builder => '_viewless_buffer',
);

# model can be launched standalone. so, make a standalone buffer.
BEGIN{
  unless (eval "Gtk3::init_check()"){
    eval "use Gtk3; Gtk3::init"; die $@ if $@;
  }
}
sub _viewless_buffer{
  my $self = shift;
  return Gtk3::TextBuffer->new;
}

has audiosync => (
  isa => 'Wordbath::Transcript::AudioSync',
  is => 'rw',
  builder => '_build_sync',
);

has _misspelled_word_tag => (
  is => 'rw',
  isa => 'Gtk3::TextTag',
);
sub _build_sync{
  my $self = shift;
  return Wordbath::Transcript::AudioSync->new (transcript_model => $self);
}
sub BUILD{
  my $self = shift;
  $self->buf->signal_connect_swapped('mark-set', \&_on_buf_mark_set, $self);
  $self->buf->signal_connect_swapped('changed', \&_on_buf_changed, $self);
  $self->buf->signal_connect_swapped('delete-range', \&on_delete_range, $self);
  my $misspelled_word_tag = $self->buf->create_tag('missp');
  $misspelled_word_tag->set("underline-set" => 1);
  $misspelled_word_tag->set("underline" => 'error');
  $self->_misspelled_word_tag( $misspelled_word_tag );
  if ($self->from_wbml){
    $self->load_wbml($self->from_wbml);
  }
}

sub _on_buf_mark_set{
  my ($self,$iter, $mark, $txt) = @_;
  $self->_on_pos_change;
}
sub _on_buf_changed{
  my ($self, $txt) = @_;
  $self->_on_pos_change;
  my ($line, $col) = $self->get_text_pos();
  $self->logger->DEBUG("buf 'changed' event. Cursor: line $line, col $col");
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

sub _on_pos_change{
  my $self = shift;
  return unless $self->blurps('pos_change');
  my ($line, $col) = $self->get_text_pos();

  #only blurp on changes. It's a change signal.
  return if $self->last_blurp_matches(pos_change => [$line,$col]);

  $self->blurp(pos_change => $line,$col);
}


sub cursor_iter{
  my $self = shift;
  my $buf = $self->buf;
  my $iter = $buf->get_iter_at_mark($buf->get_insert);
  return $iter;
}
sub current_text{
  my $self = shift;
  my $buf = $self->buf;
  my ($start, $end) = $buf->get_bounds();
  #$end->forward_char(); why?
  my $txt = $buf->get_text($start, $end, 1);
  return $txt;
}

sub insert_sync_vector_here_at_pos{
  my $self = shift;
  my %args = @_;
  die unless $args{type};
  my $buf = $self->buf;
  my $iter = $self->cursor_iter;
  $self->audiosync->vector_here_at (type => $args{type}, iter => $iter);#, pos_ns => $args{pos_ns});
}
sub audio_pos_ns_at_cursor{
  my $self = shift;
  return $self->audiosync->audio_pos_ns_at;
}

sub sync_text_to_pos_ns{
  my $self = shift;
  my $pos_ns = shift;
  $self->logger->INFO("syncing text to $pos_ns ns.");
  my $iter = $self->audiosync->iter_at_audio_pos($pos_ns);
  $self->buf->place_cursor($iter);
}
sub pos_ns_at_cursor{
  my $self = shift;
  my $buf = $self->buf;
  my $iter = $self->cursor_iter;
  my $pos_ns = $self->audiosync->audio_pos_at_iter($iter);
  $self->logger->INFO( "estimating $pos_ns ns at cursor..");
  return $pos_ns;
}

sub get_text_pos{
  my $self = shift;
  my $textiter = $self->cursor_iter;
  my $line = $textiter->get_line;
  my $col = $textiter->get_line_offset;
  return ($line, $col);
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

sub scan_for_slabels{
  my $self = shift;
  my $txt = $self->current_text;
  my @slabels;
  my $floating_spkr_lbl = qr|[^:\n]{1,40}|;
  push @slabels, $1 if $txt =~ m|^($floating_spkr_lbl):\s|;
  push @slabels, $1 while $txt =~ m|\n($floating_spkr_lbl):\s|g;
  return @slabels;
}

sub collect_slabels{
  my $self = shift;
  # extract all labels from text.
  my @slabels = $self->scan_for_slabels;
  if (@slabels >= 2){
    unshift @slabels, pop @slabels; #penultimate first..
  }
  unshift @slabels, 'Interviewer';
  unshift @slabels, 'Interviewee';
  my %seen;
  @slabels = reverse grep {not $seen{$_}++} reverse @slabels;
  $self->_slabels_to_try(\@slabels);
  $self->logger->INFO("collected labels: ".scalar @slabels);
}

sub next_slabel_in_text{
  my $self = shift;
  #my %args = @_;
  my $txt = $self->current_text;
  my $lst_lbl = $self->_last_tried_slabel;
  if ($lst_lbl and $txt =~ /\Q$lst_lbl\E:\s+$/){
    $self->logger->INFO('replacing last speaker label.');
    my $buf = $self->buf;
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
    $self->logger->INFO( 'collecting speaker label');
    $self->insert_sync_vector_here_at_pos(type => 'slabel');#pos_ns => $args{pos_ns} );;
    $self->collect_slabels;
    my $next_lbl = $self->_next_untried_slabel;
    $self->_append_slabel($next_lbl);
  }
}

sub strip_ending_whitespace{
  my $self = shift;
  my $buf = $self->buf;
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
  $self->logger->INFO( "appending speaker label $next_lbl");
  my $buf = $self->buf;
  $self->strip_ending_whitespace();
  my $end = $buf->get_end_iter();

  my $append_text = "";
  $append_text .= "\n\n" if $end->copy->backward_char; #at the beginning?
  $append_text .= "$next_lbl: ";
  $buf->insert($end, $append_text);
  #$self->scroll_to_end();
  $self->blurp('end_activity');
  $self->_last_tried_slabel($next_lbl);
}

sub append_text{
  my ($self, $text) = @_;
  my $buf = $self->buf;
  my $end = $buf->get_end_iter();
  $buf->insert($end, $text);
}
sub append_line{
  my ($self, $line) = @_;
  my $buf = $self->buf;
  my $end = $buf->get_end_iter();
  $line = "\n\n$line" if $end->copy->backward_char; #at the beginning?
  $buf->insert($end, $line);
}

sub insert_time_ns{
  my ($self, $time_ns) = @_;
  my $str = _fmt_time_ns($time_ns);
  my $i= $self->buf->get_iter_at_mark($self->buf->get_insert);
  $self->buf->insert($i, $str);
}

# example: 3700*BILLION -> "01:01:40"
# potentially modifiable, unlike the same thing in App.pm
sub _fmt_time_ns{
  my $ns = shift;
  my $tot_sec = int ($ns / 10**9);
  my $sec = $tot_sec % 60;
  my $time_txt = sprintf ("%02d", $sec);
  my $min = int($tot_sec/60) % 60;
  $time_txt = sprintf("%02d:$time_txt", $min);
  #hours
  if ($tot_sec >= 3600){
    my $hr = int($tot_sec / 3600);
    $time_txt = sprintf("%02d:$time_txt", $hr);
  }
  return $time_txt;
}


#### UNDO / REDO
{
  package Wordbath::Transcript::Model::DoDo;
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
  my $dodo = Wordbath::Transcript::Model::DoDo->new(@_);
  $self->clear_redo;

  $self->push_undo($dodo);
  if($self->count_undo > 100){
    $self->shift_undo;
    $self->logger->DEBUG('forgetting oldest undo.');
  }
  $self->logger->DEBUG('undoable op captured.');
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
    $self->logger->DEBUG('undo initiated.');
    $undo->undo();
    $self->logger->DEBUG('undo executed.');
  };
  $self->unsuppress_dodo;
  $self->push_redo($undo);
}
sub redo {
  my $self = shift;
  return unless $self->has_redo;
  my $redo = $self->pop_redo;
  $self->suppress_dodo;
  eval{
    $self->logger->DEBUG('redo initiated.');
    $redo->redo();
    $self->logger->DEBUG( 'redo executed.');
  };
  $self->unsuppress_dodo;
  $self->push_undo($redo);
}

# related to undo. If a key's was held pressed as a modifier, delete its insertion.
sub arbitrary_text_retraction{
  my ($self, $char, $mult) = @_;
  my $buf = $self->buf;

  my ($start, $end) = $buf->get_bounds();
  $self->suppress_dodo;
  eval{
    for (1..$mult){
      my $i = $self->cursor_iter;
      my $j = $self->cursor_iter;
      $i->backward_char;
      my $t = $buf->get_text($i,$j, 1);
      return unless $t eq $char;
      $buf->delete($i,$j);
    }
  };
  $self->unsuppress_dodo;
}

##### SPELLCHECK STUFF
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
  my $specific_word = shift;
  if ($specific_word){
    my @w = values @{$self->_misspelled_words->{$specific_word}};
    return @w;
  }
  # all.
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

has speller_widget => (
  is => 'rw',
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

sub spellcheck_range {
  my ($self, $range_start, $range_end) = @_;
  # expand range to encompass words partially overlapping range.
  my $buf = $self->buf;
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

sub on_ignoring_missp{
  my ($self,$word_txt) = @_;
  my @missp_words = $self->all_misspelled_words($word_txt);
  $self->remove_misspelled_word($_) for @missp_words;
}

sub spellcheck_all{
  my $self = shift;
  #reset the misspelled word widget
  $self->speller_widget->clear_missps; 
  #remove those little red underlines:
  my @missp_words = $self->all_misspelled_words;
  $self->remove_misspelled_word($_) for @missp_words;

  my ($start, $end) = $self->buf->get_bounds();
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
    $self->speller_widget->add_missp($word, $res);
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
use JSON;
use File::Slurp;
sub save_vectors{
  my ($self, $path) = @_;
  my $json = encode_json ($self->audiosync->to_hash);
  write_file($path, {binmode => ':utf8'}, $json);
  $self->logger->NOTICE("wrote sync vectors to $path");
}

### LOAD
sub load_wbml{
  my ($self, $wbml_path) = @_;
  my $doc = XML::LibXML->new->parse_file($wbml_path);
  my $transcript_e = $doc->documentElement();
  my @cn = $transcript_e->childNodes;
  my %spkrs;
  my $pnum = 0;
  for my $node (@cn){
    next if $node->nodeType == XML_TEXT_NODE; #whitespace in xml?
    if ($node->localname eq 'speaker'){
      $spkrs{$node->getAttribute('id')} = $node;
    }
    elsif ($node->localname eq 'speakerless-event'){
      $self->append_text("\n\n") if ($pnum>0);
      $self->append_text( '[' . $node->textContent . ']');
      $pnum++
    }
    elsif ($node->localname eq 'paragraph'){
      $self->append_text("\n\n") if ($pnum>0);
      my $spkr_id = $node->getAttribute('speaker');
      if($spkr_id){
        my $spkr_node = $spkrs{$spkr_id};
        $self->append_text($spkr_id . ': ');
      }
      for my $p_c ($node->childNodes){
        if ($p_c->nodeType == XML_TEXT_NODE){
          $self->append_text($p_c->nodeValue);
        } elsif ($p_c->localname eq 'speaker-event'){
          $self->append_text( '[' . $p_c->textContent . ']');
        } elsif ($p_c->localname eq 'alignment-vector'){
          $self->audiosync->vector_here_at (
            iter => $self->buf->get_end_iter,
            pos_ns => $p_c->getAttribute('audio-pos-ns'),
            type => $p_c->getAttribute('classification'),
          );
        }
      }
      $pnum++
    }
    else {die $node->localname .', '. $node->nodeType};
  }
}

### SAVE

# return libxml doc based on current state
sub _wbml_doc{
  my $self = shift;
  my $doc = XML::LibXML->createDocument;
  my $root = $doc->createElementNS( "", "transcript" );
  $doc->setDocumentElement( $root );

  for my $slabel ($self->scan_for_slabels){
    my $sl_e = $doc->createElement( "speaker" );
    $sl_e->setAttribute(id => $slabel);
    $root->appendChild($sl_e);
  }
  # iterate through the buffer, picking out paragraphs and such
  my $buf = $self->buf;
  my ($line_iter, $end) = $buf->get_bounds();
  my $lnum = 0;
  my $last_lnum = $end->get_line;
  for my $lnum (0 .. $last_lnum){
    $line_iter->set_line($lnum);
    my $line_end = $line_iter->copy;
    $line_end->forward_line;
    $line_end->backward_char unless $lnum == $last_lnum;
    my $l_txt = $buf->get_text($line_iter, $line_end, 1);
    if ($l_txt eq ''){
      #blank line. do nothing.
    } elsif ($l_txt =~ /^\[(.*)\]$/){
      my $e = $root->addNewChild('', 'speakerless-event');
      my $ec = $doc->createTextNode( $1 );
      $e->addChild( $ec );
    } else {
      $l_txt =~ /^([^:]{1,40}): (.*)$/;
      my $slabel = $1;
      my $rest_of_line = $1 ? $2 : $l_txt;

      my $p = $root->addNewChild('', 'paragraph');
      $p->setAttribute(speaker => $slabel) if $slabel;

      my $pending_text = '';
      my $flush_pending_text = sub{
        return unless $pending_text;
        my $text = $doc->createTextNode($pending_text);
        $p->appendChild($text);
        $pending_text = '';
      };
      my $react_to_marks = sub{
        my $i = shift;
        my $marks = $i->get_marks || [];
        for (@$marks){
          # is this mark an alignment vector position?
          my $vec = $self->audiosync->vector_from_mark($_);
          if ($vec){
            $flush_pending_text->();
            my $vec_node = $p->addNewChild('', 'alignment-vector');
            $vec_node->setAttribute('audio-pos-ns' => $vec->pos_ns);
            $vec_node->setAttribute('classification' => $vec->type);
          }
        }
      };

      my $char_i = $line_iter->copy;
      $char_i->forward_chars(length "$slabel: ") if $slabel;
      until ($char_i->equal($line_end)){
        $react_to_marks->($char_i); #find alignment vectors.
        my $ch = $char_i->get_char;

        if ($ch eq '['){ #speaker-event, e.g. [honks while slurping]
          my $eoe = $char_i->copy;
          my $e_text = ''; #event text
          $eoe->forward_find_char(sub{my $ech=shift; $e_text.=$ech; $ech eq ']'},'', $line_end);
          chop $e_text; # -']'

          if ($eoe->equal($line_end)) { #no closing tag found.
            $pending_text .= $ch;
            $char_i->forward_char;
            next;
          }

          my $markfind_i = $char_i->copy;
          until ($markfind_i->equal($eoe)){
            #find alignment vectors left inside the event tag.
            $react_to_marks->($markfind_i);
            $markfind_i->forward_char;
          }
          $react_to_marks->($markfind_i); #find alignment vectors on closing tag

          my $text_node = $doc->createTextNode($e_text);
          my $se = $p->addNewChild('', 'speaker-event');
          $se->appendChild($text_node);
          $char_i = $eoe;
          $char_i->forward_char;
        } else { #normal. no event tag found.
          $pending_text .= $ch;
          $char_i->forward_char;
        }
      }
      $flush_pending_text->();
    }
    $lnum++
  }
  return $doc;
}
sub save_wbml{
  my ($self, $wbml_path) = @_;
  my $doc = $self->_wbml_doc;
  $doc->toFile($wbml_path, 2);
}
sub to_wbml{
  my $self = shift;
  my $doc = $self->_wbml_doc;
  return $doc->toString(2);
}

1;
