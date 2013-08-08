package Wordbath::Whenever;
use Moose::Role;
use Modern::Perl;
use Array::Compare;

# This role has only been tested with singletons.

use Moose::Exporter;
Moose::Exporter->setup_import_methods(
  with_meta => [ 'signal' ],
);

# $data will be the first argument,
#  so the handler can be a method of whatever $data is.
has _signals => (
  is => 'ro',
  isa => 'HashRef',
  default => sub{{}},
  #default => sub{{pos_change => [],}},
);
has _last_blurps =>(
  is => 'ro',
  isa => 'HashRef',
  default => sub{{}},
);

# Only try to read this if you understand Moose.
# 'signal' is a keyword, callable from classes that use this role.
sub signal {
  my $meta = shift;
  my $sig_name = shift;
  my $sigs_attr = $meta->get_attribute('_signals');
  my $sig_attr_default = $sigs_attr->{default}->();
  die "signal($sig_name) redefined." if $sig_attr_default->{$sig_name};
  $sig_attr_default->{$sig_name} = [];
  $sigs_attr->{default} = sub{$sig_attr_default};
}

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
     unless $self->_signals->{$signal_name};
  my $last_blurp = $self->last_blurp($signal_name);
  return 0 unless defined $last_blurp;
  my $comp = Array::Compare->new();
  return $comp->simple_compare ($blurp, $last_blurp);
}
1

