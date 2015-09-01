package Wordbath::Config;
use Moose;
use Modern::Perl;
use JSON;
use Path::Tiny;

has config_file_path => (
  isa => 'Str',
  is => 'ro',
  default => $ENV{HOME} . '/.wordbath.json',
);
has edit_window => (
  isa => 'Gtk3::Window',
  is => 'rw',
  clearer => 'reset_edit_window',
);

has working_dir => (
  is => 'rw',
  isa => 'Str',
  default => '/tmp/wordbath',
);

#constructor.....
sub load_or_create{
  my $class = shift;
  my $self  = __PACKAGE__->new(@_);
  #class defaults are good enough?
  return $self unless (-e $self->config_file_path);

  my $json = path( $self->config_file_path)->slurp_utf8;
  my $conf_data = decode_json($json);
  $self->working_dir($conf_data->{working_dir});
  return $self;
}
sub save{
  my $self = shift;
  my $json = encode_json ({
      working_dir => $self->working_dir,
      # don't encode config file path. what if you move the file? why would it help?
    });
  my $cpath = $self->config_file_path;
  path($cpath)->spew_utf8($json);
  say "wrote config to $cpath";
}

sub launch_edit_window{
  my $self = shift;
  $self->edit_window->destroy if $self->edit_window;

  my $win = Gtk3::Window->new();
  my $grid = Gtk3::Grid->new();
  $win->add($grid);

  my $l = Gtk3::Label->new('Working directory');
  $grid->attach($l,0,0,2,1);
  my $fchoose = Gtk3::FileChooserButton->new('Select working dir', 'select-folder');
  $fchoose->set_current_folder($self->working_dir);
  $grid->attach($fchoose,2,0,1,2);

  my $sav = Gtk3::Button->new('Save');
  my $cancel = Gtk3::Button->new('Cancel');
  $grid->attach($sav,0,1,1,2);
  $grid->attach($cancel,1,2,2,1);
  $cancel->signal_connect(clicked => sub{$win->destroy});
  $sav->signal_connect(clicked => sub{
      $self->working_dir($fchoose->get_current_folder());
      $self->save();
      $win->destroy();
    });

  $grid->attach(Gtk3::Label->new('foo'),1,1,1,1);

  $win->signal_connect(destroy => sub{$self->reset_edit_window()});
  $self->edit_window($win);
  $win->show_all();
}
1

