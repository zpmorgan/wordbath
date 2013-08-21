package Wordbath::App::ArbitKeys;
use Moose;
use Modern::Perl;
use Time::HiRes qw/time/;

with 'Wordbath::Whenever';
Wordbath::Whenever->import();
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
    die "eval broke, of Gtk3::Gdk::KEY_$key";
  }
  return $code;
}

my $arbitthreshold_ms = 120;

sub do_press_event{ # gdk
  my ($self, $e) = @_;
  my $val = $e->keyval;

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
    for (@combos_for_key){
      my $mod = $_->modcode;
      next unless $self->_keys_down->{$mod};
      my $how_long_held = $ms - $self->_keys_down->{$mod};
      next if $how_long_held < $arbitthreshold_ms; #hold it down for longer.
      $combo = $_;
      last;
    }
  }

  # nothing found? then maybe it's a ratractable mod that's being pressed. Track if so.
  unless ($combo){
    if ($val < 128){
      my $ch = lc chr $val;
      if (defined($self->_last_down) and $self->_last_down eq $ch){
        $self->inc_last_down_mult;
      } else {
        $self->_last_down($ch);
        $self->clear_last_down_mult;
        $self->inc_last_down_mult;
      }
    }
    return 0 
  }

  # run the found hotkey callback.
  $combo->cb->();

  if ($combo->is_retractable){ #retract if the mod left a mark in the transcript.
    if (defined($self->_last_down) and ($self->_last_down eq  $combo->modifier)){
      my $ch = $combo->modifier;
      say "retracting. ch: $ch, mult: ". $self->_last_down_mult;
      $self->blurp('retraction', $combo->modifier, $self->_last_down_mult);
      $self->clear_last_down;
      $self->clear_last_down_mult;
    }
  }
  return 1;
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

sub do_release_event{
  my ($self,$e) = @_;
  my $val = $e->keyval;
  #my $key_text = Gtk3::Gdk::keyval_to_unicode($val);
  if ($val < 128){
    my $ch = lc chr($val);
    if (defined($self->_last_down) and ($self->_last_down eq $ch)){
      $self->clear_last_down;
      $self->clear_last_down_mult;
    }
  }
  delete $self->_keys_down->{$val};
}
1;

