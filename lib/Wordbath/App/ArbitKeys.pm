package Wordbath::App::ArbitKeys;
use Moose;
use Modern::Perl;
use Time::HiRes qw/time/;

with 'Wordbath::Whenever';
Wordbath::Whenever->import();
# keypress was a modifier.
signal ('retraction');

has [qw/_keys_down _combos_by_key/] => (
  is => 'ro',
  isa => 'HashRef',
  default => sub{{}},
);

# $ak->handle (keycombo => "<shift>J", cb=>sub{foo})
sub handle{
  my ($self, %args) = @_;
  $args{keycombo} =~ /^(?|<(.*)>|())(.*)$/;
  my $mod = $1;
  my $key = $2;
  die $args{keycombo} unless defined($mod) and ($key);
  my $code = $self->_get_code($key);
  my $mod_code = $self->_get_code($mod);
  $self->_combos_by_key->{$code}{$mod_code} = $args{cb};
  #warn "self->_combos_by_key->{$code}{$mod_code} = $args{cb}";
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

  my $ch; # set if, say, a letter key.
  if ($val < 128){
    $ch = lc chr($val);
  }

  my $ms = time() * 1000;
  $self->_keys_down->{$val} //= $ms;

  my $mod = 'none';
  if ($e->state * 'shift-mask'){
    $mod = 'shift';
  }
  my $cb = $self->_combos_by_key->{$val}{$mod};
  unless ($cb){
    my @downs = keys %{$self->_keys_down};
    for my $d (@downs){
      next if $val == $d; #press can't equal modifier.
      my $how_long_held = $ms - $self->_keys_down->{$d};
      next if $how_long_held < $arbitthreshold_ms; #hold it down for longer.
      #use a down key as an arbitrary modifier.
      $mod = $d;
      $cb = $self->_combos_by_key->{$val}{$mod};
      last if $cb;
    }
  }

  # nothing found? then maybe it's a ratractable mod that's being pressed. Track if so.
  unless ($cb){
    if(defined ($ch)){
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
  $cb->();

  if ($ch){
    if (defined($self->_last_down) and ($self->_last_down eq chr $mod)){
      say "retracting. ch: $ch, mult: ". $self->_last_down_mult;
      $self->blurp('retraction', chr $mod, $self->_last_down_mult);
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

