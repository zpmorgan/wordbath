#!/usr/bin/env perl
use warnings;
use strict;

use FindBin qw'$Bin';
use lib $Bin . '/lib';
use Wordbath::Player;
use Wordbath::App;

my $wb;
$wb = Wordbath::App->new();

$wb->load_audio_file('dchha48_Prophets_of_Doom.mp3');
$wb->play();

$wb->run();

