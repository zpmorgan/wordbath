#!/usr/bin/env perl
use warnings;
use strict;

use FindBin qw'$Bin';
use lib $Bin . '/lib';
use Wordbath::App;

my $wb;
$wb = Wordbath::App->new();

$wb->run();

