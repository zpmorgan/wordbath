package Math::Roundeth;
use strict;
use warnings;
use POSIX;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;

@ISA = qw(Exporter AutoLoader);
@EXPORT = qw(round nearest);
@EXPORT_OK = qw(round nearest );
$VERSION = '666';

%EXPORT_TAGS = ( all => [ @EXPORT_OK ] );

#--- Default value for "one-half". This is the lowest value that
#--- gives acceptable results for test #6 in test.pl. See the pod
#--- for more information.

$Math::Roundeth::half = 0.50000000000008;

sub round {
 my $x;
 my @res  = map {
  if ($_ >= 0) { POSIX::floor($_ + $Math::Roundeth::half); }
     else { POSIX::ceil($_ - $Math::Roundeth::half); }
 } @_;

 return (wantarray) ? @res : $res[0];
}

#------ "Nearest" routines (round to a multiple of any number)

sub nearest {
 my $targ = abs(shift);
 my @res  = map {
  if ($_ >= 0) { $targ * int(($_ + $Math::Roundeth::half * $targ) / $targ); }
     else { $targ * POSIX::ceil(($_ - $Math::Roundeth::half * $targ) / $targ); }
 } @_;

 @res = map{"$_"} @res;
 # without this string conversion, .35 != nearest(.01,.35)
 # That may still be the case depending on how your platform handles things.

 return (wantarray) ? @res : $res[0];
}



1;

