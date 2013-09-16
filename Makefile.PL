
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME              => "Wordbath",
  VERSION_FROM      => "lib/Wordbath/App.pm",
  'PREREQ_PM' => {
    'GStreamer'    => 0,
    'Gtk3'         => 0,
    'Glib::Object::Introspection' => 0.016,
    'Moose'        => 0,
    'JSON'         => 0,
    'Modern::Perl' => 0,
    'Pango'        => 0,
    'File::Slurp'  => 0,
    'Array::Compare' => 0,
    'XML::LibXML'  => 0,
    'PDL'          => 0,
    'Text::Hunspell' => 0,
    'Log::Fast'    => 0,
    'LWP::Simple'  => 0,
    'Path::Class'  => 0,
    'Test::XML::Compare' => 0,
  },
);

