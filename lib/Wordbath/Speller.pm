package Wordbath::Speller;
use Moose;
use Modern::Perl;
#use Gtk3;

has widget => (
  builder => '_build_widget',
  isa => 'Gtk3::Box',
  is => 'ro',
);

has _missp_ls => (
  is => 'ro',
  isa => 'Gtk3::ListStore',
  builder => '_build_missp_ls',
  lazy => 1,
);
has _candidates_ls => (
  is => 'ro',
  isa => 'Gtk3::ListStore',
  builder => '_build_candidates_ls',
  lazy => 1,
);
has _missp_view => (
  is => 'ro',
  isa => 'Gtk3::TreeView',
  builder => '_build_missp_view',
  lazy => 1,
);
has _candidates_view => (
  is => 'ro',
  isa => 'Gtk3::TreeView',
  builder => '_build_candidates_view',
  lazy => 1,
);

sub _build_widget{
  my $self = shift;
  my $vb = Gtk3::Box->new('vertical',3);
  my $spell_label = Gtk3::Label->new('REMINDER: SPELL CORRECTLY');
  my $spell_label2= Gtk3::Label->new('DOIT! ' . $self->_check_word('12ad'));
  #$_->get_style_context->remove_class("background")
  #  for ($vb,$spell_label);
  $vb->pack_end($self->_missp_view,0,0,0);
  $vb->pack_end($self->_candidates_view,0,0,0);
  $vb->pack_start($spell_label,0,0,0);
  $vb->pack_end($spell_label2,0,0,0);
  for(qw/foo bar baz/){
    my $iter = $self->_missp_ls->append;
    $self->_missp_ls->set($iter, 0, $_);
  }
  return $vb;
}

sub _build_candidates_ls{
  my $self = shift;
  return Gtk3::ListStore->new(qw/Glib::String/);
}
sub _build_missp_ls{
  my $self = shift;
  return Gtk3::ListStore->new(qw/Glib::String/);
}
sub _build_candidates_view {
  my $self = shift;
  return Gtk3::TreeView->new($self->_candidates_ls);
}
sub _build_missp_view{
  my $self = shift;
  my $tree = Gtk3::TreeView->new($self->_missp_ls);
  my $renderer = Gtk3::CellRendererText->new();
  my $column = Gtk3::TreeViewColumn->new_with_attributes(werds => $renderer, text=>0);
  $tree->append_column($column);
  return $tree;
}


use IPC::Open3;

say 'Spell checker initializing. Hold your breath please.';
my ($sp_in,$sp_out,$sp_err);
use Symbol 'gensym'; $sp_err = gensym;
my $pid = open3 ($sp_in, $sp_out, $sp_err, 'hunspell -');
my $res =  <$sp_out>;
#print $sp_in "foo\nfoo\n";
if ($res =~ /^Hunspell/){
  say 'Spell checker initialized. You may breathe.'
}
else {
  say 'hunspell messed up?';
}


sub _check_word{
  my ($self, $word) = @_;
  if ($word =~ /\s/){
    die "please dont pollute spell checker with whitespace. ($word)";
  }
  print $sp_in "$word\n";
  my $res = <$sp_out>;
  return $res;
}

1;

