package Wordbath::App::ArbitKeys;
use Moose;
use Modern::Perl;
use Time::HiRes qw/time/;

with 'Wordbath::Roles::Logger';
with 'Wordbath::Roles::Whenever';
Wordbath::Roles::Whenever->import();
# 'retraction' is spewed when the previous keypress
# turns out to be a modifier.
signal ('retraction');

{
  package Wordbath::App::ArbitKeys::Combo;
  use Moose;
  use Modern::Perl;
  has pattern => ( isa => 'Str', is => 'ro');
  has key => ( isa => 'Str', is => 'ro',lazy => 1, builder => '_key_from_pattern');
  has modifier => ( isa => 'Str', is => 'ro',lazy => 1, builder => '_mod_from_pattern');
  has cb => ( isa => 'CodeRef', is => 'ro',required => 1);
  has is_retractable => ( isa => 'Bool', is => 'ro', lazy => 1, builder => '_determine_retractability');

  # modifier retractability
  sub _determine_retractability{
    my $self = shift;
    return 1 if $self->modifier =~ /^.$/;
    return 0;
  }
  sub _key_from_pattern{
    my $self = shift;
    die 'no pattern' unless $self->pattern;
    $self->pattern =~ /^(<.*>)?(.*)$/;
    return $2;
  }
  sub _mod_from_pattern{
    my $self = shift;
    die 'no pattern' unless $self->pattern;
    $self->pattern =~ /^(?|<(.*)>|())(.*)$/;
    return $1;
  }

  # codes: keyvals with gdk inconsistencies fixed?
  # and 'mask' keys, such as shift, are named instead.
  # (KEY_leftarrow, etc.)
  sub keycode{
    my $self = shift;
    my $code = Wordbath::App::ArbitKeys->_get_code($self->key);
  }
  sub modcode{
    my $self = shift;
    my $code = Wordbath::App::ArbitKeys->_get_code($self->modifier);
  }
}

has [qw/_keys_down _combos_by_mod _combos_by_key/] => (
  is => 'ro',
  isa => 'HashRef',
  default => sub{{}},
);

# $ak->handle (keycombo => "<shift>J", cb=>sub{foo})
sub handle{
  my ($self, %args) = @_;
  # $args{keycombo} =~ /^(?|<(.*)>|())(.*)$/;
  my $combo = Wordbath::App::ArbitKeys::Combo->new( pattern => $args{keycombo} , cb => $args{cb} );
  my $code = $combo->keycode;
  my $mod_code = $combo->modcode;
  push @{$self->_combos_by_key->{$code}}, $combo; 
  push @{$self->_combos_by_mod->{$mod_code}}, $combo; 
}

# used to set up combo structure, maps names to gdk codes
sub _get_code{
  my ($self, $key) = @_;
  return 'none' if $key eq ''; #no modifier, hopefully
  return 'shift' if($key eq 'shift');
  if($key eq 'left'){
    return 65361; # not the same as Gtk3::Gdk::KEY_leftarrow?
  } if ($key eq 'right'){
    return 65363;
  }

  if ($key eq ';'){
    $key = 'semicolon'
  }
  my $code = eval "Gtk3::Gdk::KEY_$key";
  if ($@){
    $self->logger->ERR("eval broke, of Gtk3::Gdk::KEY_$key");
    die "eval broke, of Gtk3::Gdk::KEY_$key";
  }
  return $code;
}

my $arbitthreshold_ms = 720;

sub do_press_event{ # gdk
  my ($self, $e) = @_;
  my $val = $e->keyval;
  $self->_drop_pending_combo;

  my $ms = time() * 1000;
  $self->_keys_down->{$val} //= $ms;

  my @combos_for_key = @{ $self->_combos_by_key->{$val} // []};
  my $combo;
  if ($e->state * 'shift-mask'){
    my $mod = 'shift';
    for (@combos_for_key){
      $combo = $_ if ($_->modifier eq 'shift')
    }
  }
  unless ($combo) {
    for my $potent_combo (@combos_for_key){
      my $mod = $potent_combo->modcode;
      if ($mod eq 'none'){ #plain F5, for example
        $combo = $potent_combo;
        last;
      }
      next unless $self->_keys_down->{$mod};
      my $how_long_held = $ms - $self->_keys_down->{$mod};
      if ($how_long_held < $arbitthreshold_ms){
        # mod is not held for long enough, so
        # trigger later on either condition:
        #   * it's held for a bit longer.
        #   * 2nd key is released first.
        $self->_pending_combo($potent_combo);
        if (defined($self->_last_down) and ($self->_last_down eq  $potent_combo->modifier)){
          $self->_pending_char_retraction($self->_last_down);
          $self->_pending_char_mult($self->_last_down_mult);
          $self->logger->INFO("self->_pending_char_retraction(".$self->_last_down);
        }
        my $to = Glib::Timeout->add ( $arbitthreshold_ms - $how_long_held, sub{
            $potent_combo->cb->();
            # retract pending retraction.
            $self->retract_last_down;
            $self->_retract_pending_combo_retractables;
            $self->_drop_pending_combo;
            return 0;
          });
        $self->_pending_timeout_i($to);
        $self->_track_last_down($val);
        return 0;
      }
      $combo = $potent_combo;
      last;
    }
  }

  # nothing found? then maybe it's a ratractable mod that's being pressed. Track if so.
  unless ($combo){
    $self->_track_last_down($val);
    return 0 
  }


  # run the found hotkey callback.
  $combo->cb->();

  if ($combo->is_retractable){ #retract if the mod left a mark in the transcript.
    if (defined($self->_last_down) and ($self->_last_down eq  $combo->modifier)){
      $self->retract_last_down();
    }
  }
  return 1;
}

sub _track_last_down{
  my ($self, $val) = @_;
  if ($val < 128){ # ascii ~~ key retractables.
    my $ch = lc chr $val;
    if (defined($self->_last_down) and $self->_last_down eq $ch){
      $self->inc_last_down_mult;
    } else {
      $self->_last_down($ch);
      $self->clear_last_down_mult;
      $self->inc_last_down_mult;
    }
  }
}

# should just be for modifiers that would insert text
has _last_down => (
  is => 'rw',
  isa => 'Str',
  clearer => 'clear_last_down',
);
has _last_down_mult => (
  is => 'rw',
  isa => 'Int',
  default => 0,
  traits  => ['Counter'],
  handles => {
    clear_last_down_mult => 'reset',
    inc_last_down_mult => 'inc',
  },
);
sub retract_last_down{
  my $self = shift;
  my $ch = $self->_last_down;
  $self->logger->INFO("retracting. ch: $ch, mult: ". $self->_last_down_mult);
  $self->blurp('retraction', $ch, $self->_last_down_mult);
  $self->clear_last_down;
  $self->clear_last_down_mult;
}

sub do_release_event{
  my ($self,$e) = @_;
  my $val = $e->keyval;
  delete $self->_keys_down->{$val};

  # possibly trigger the pending hotkey combo
  # drop the pending combo either way
  # why keep it? It's a release evet.
  if ($self->_pending_combo){
    if ($val == $self->_pending_combo->keycode){
      $self->retract_last_down;
      $self->_retract_pending_combo_retractables;
      $self->_pending_combo->cb->();
    }
    $self->_drop_pending_combo;
  }

  if ($val < 128){
    my $ch = lc chr($val);
    if (defined($self->_last_down) and ($self->_last_down eq $ch)){
      $self->clear_last_down;
      $self->clear_last_down_mult;
    }
  }
}
has _pending_timeout_i => (is => 'rw',isa => 'Int', clearer => '_foo4');
has _pending_combo => (
  is => 'rw',isa => 'Wordbath::App::ArbitKeys::Combo', clearer => '_foo3',
  predicate => 'combo_pending');
has _pending_char_retraction => (
  is => 'rw',isa => 'Str', clearer => '_foo2',
  predicate => 'combo_retraction_pending');
has _pending_char_mult => (is => 'rw',isa => 'Int', clearer => '_foo1');
sub _drop_pending_combo{
  my $self = shift;
  return unless $self->combo_pending;
  $self->_foo1;
  $self->_foo2;
  $self->_foo3;
  Glib::Source->remove($self->_pending_timeout_i);
  $self->_foo4;
}
sub _retract_pending_combo_retractables{
  my $self = shift;
  return unless $self->combo_retraction_pending;
  my $ch = $self->_pending_char_retraction;
  my $mult= $self->_pending_char_mult;
  $self->logger->INFO("retracting (was pending). ch: $ch, mult: ". $mult);
  $self->blurp('retraction', $ch, $mult);
  # insignificant: foo2; foo1;
}

# return a string.
sub infodump{
  my $self = shift;
  my $kd = join "\n", keys %{$self->_keys_down};
  my $crap = join "\n", map{$_ .' | '. $self->{$_}} keys %$self;
  my $combos = 'foo';

  my $dump = <<"EOD";
  KEYS DOWN: \n$kd\n\n
  CRAP:\n$crap\n\n
  COMBOS:\n$combos\n\n
EOD
  return $dump;
}

1;

