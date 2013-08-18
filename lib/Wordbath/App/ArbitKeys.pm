package Wordbath::App::ArbitKeys;
use Moose;
use Modern::Perl;
use Time::HiRes qw/time/;

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

sub do_press_event{ # gdk
  my ($self, $e) = @_;
  my $val = $e->keyval;

  my $arbitthreshold_ms = 200;

  my $ms = time() * 1000;
  $self->_keys_down->{$val} = $ms;

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
      $cb = $self->_combos_by_key->{$val}{$d};
      last if $cb;
    }
  }
  return 0 unless $cb;
  $cb->();
  return 1;
}
sub do_release_event{
  my ($self,$e) = @_;
  my $val = $e->keyval;
  delete $self->_keys_down->{$val};
}
1;

