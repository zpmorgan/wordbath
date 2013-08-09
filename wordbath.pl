#!/usr/bin/env perl
use Modern::Perl;

use FindBin qw'$Bin';
use lib $Bin . '/lib';
use Wordbath::App;
use Wordbath::Player;

my $location = $ARGV[0];

#these depend entirely on what is being loaded.
my $workdir;
my $file;

if ($location){
  #is it a url? if so, do we have to download?
  if ($location =~  m|^https?://.*/([^/]*\.[^/]{2,}+)$| ){
    $file = $1;
    $workdir = '/tmp/wordbath';
    mkdir $workdir unless -d $workdir;
    if (-e "$workdir/$file"){
      say "$file already exists in $workdir.";
    } else {
      use LWP::Simple;
      my $data = get $location;
      die 'audio download failed.' unless defined($data);

      use File::Slurp;
      write_file( "$workdir/$file", $data);
      say "Saved as $file    in directory:   $workdir";
    }
  }else {
    #given a filesystem path.
    use Path::Class;
    my $path = file ($location);
    $workdir = $path->dir->absolute->stringify;
    $file = $path->basename;
  }
}
else{
  $file = 'dchha48_Prophets_of_Doom.mp3';
  $workdir = $Bin;
}

my $wb;
$wb = Wordbath::App->new();
$wb->load_audio_file("$workdir/$file");
$wb->play();

$wb->run();

