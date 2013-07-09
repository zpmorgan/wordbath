package Wordbath::App;
use Moose;
use Gtk3 -init;

#gtk3 stuff.

has win => (
  isa => 'Gtk3::Window',
  is => 'ro',
  lazy => 1,
  builder => '_build_win',
);

sub _build_win{
  my $self = shift;
  my $win = Gtk3::Window->new();
  $win->show_all();
  $win->signal_connect (destroy => sub { Gtk3::main_quit });
  return $win;
}

sub run{
  my $self = shift;
  $self->win;
  Gtk3::main;
}


1;


