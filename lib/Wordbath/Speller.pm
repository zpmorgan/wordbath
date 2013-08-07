package Wordbath::Speller;
use Moose;
use Modern::Perl;
#use Gtk3;

has widget => (
  builder => '_build_widget',
  isa => 'Gtk3::Box',
  is => 'ro',
);

sub _build_widget{
  my $self = shift;
  my $vb = Gtk3::Box->new('vertical',3);
  my $spell_label = Gtk3::Label->new('REMINDER: SPELL CORRECTLY');
  my $spell_label2= Gtk3::Label->new('DOIT!');
  #$_->get_style_context->remove_class("background")
  #  for ($vb,$spell_label);
  $vb->pack_start($spell_label,0,0,0);
  $vb->pack_end($spell_label2,0,0,0);
  return $vb;
}

1;

