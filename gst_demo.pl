#!/usr/bin/env perl
use Modern::Perl;
use FindBin '$Bin';

use GStreamer -init;

my $file= '/dchha48_Prophets_of_Doom.mp3';
my $path = $Bin . '/' . $file;
  my $loop = Glib::MainLoop -> new();

  # set up
  my $play = GStreamer::ElementFactory -> make("playbin", "play");
  $play -> set(uri => Glib::filename_to_uri $path, "localhost");
  $play -> get_bus() -> add_watch(\&my_bus_callback, $loop);
  $play -> set_state("playing");

  # run
  $loop -> run();

  # clean up
  $play -> set_state("null");

  sub my_bus_callback {
    my ($bus, $message, $loop) = @_;

    if ($message -> type & "error") {
      warn $message -> error;
      $loop -> quit();
    }

    elsif ($message -> type & "eos") {
      $loop -> quit();
    }

    # remove message from the queue
    return 1;
  }
