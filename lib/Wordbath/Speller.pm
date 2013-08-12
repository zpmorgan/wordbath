package Wordbath::Speller;
use Moose;
use Modern::Perl;
use utf8;
#use Gtk3;

has widget => (
  builder => '_build_widget',
  isa => 'Gtk3::Box',
  is => 'ro',
);

has check_all_button => (
  isa => 'Gtk3::Button',
  is => 'ro',
  lazy => 1,
  builder => '_build_checkall_button',
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
  #my $spell_label2= Gtk3::Label->new('DOIT! ' . $self->check_word('12ad'));
  #$_->get_style_context->remove_class("background")
  #  for ($vb,$spell_label);
  $vb->pack_start($self->check_all_button, 0,0,0);
  #$vb->pack_start($spell_label,0,0,0);
  $vb->pack_end($self->_missp_view,0,0,0);
  #$vb->pack_end($self->_candidates_view,0,0,0);
  $vb->pack_end($spell_label,0,0,0);
  return $vb;
}
sub _build_checkall_button{
  return Gtk3::Button->new('Spell-check all');
}

sub _build_candidates_ls{
  my $self = shift;
  return Gtk3::ListStore->new(qw/Glib::String/);
}
sub _build_missp_ls{
  my $self = shift;
  my $model = Gtk3::ListStore->new(qw/Glib::String/);
  for(qw/1 2 3 4/){
    my $iter = $model->append;
    $model->set($iter, 0, $_);
  }
  my $i = $model->get_iter_first();
  $i = $model->remove($i);
  return $model;
}
sub _build_candidates_view {
  my $self = shift;
  return Gtk3::TreeView->new($self->_candidates_ls);
}
sub _build_missp_view{
  my $self = shift;
  my $tree = Gtk3::TreeView->new;
  $tree->set_model($self->_missp_ls);
  my $ren_text = Gtk3::CellRendererText->new();
  #$ren_text->set_property('editable', 1);
  #$ren_text->signal_connect (edited => \&cell_edited, $self);
  my $column = Gtk3::TreeViewColumn->new_with_attributes(werds => $ren_text, text=>0);
  $tree->append_column($column);
  return $tree;
}

sub cell_edited {
  my ($cell, $path, $value, $self) = @_;
  my $tv = $self->_missp_view;
  warn "changing treeview $tv";
  my $model = $tv->get_model;
  #my $model = $self->_missp_ls;
  my $path_str = Gtk3::TreePath->new($path);
  my $iter = $model->get_iter($path_str);
  $model->set($iter, 0, $value);
    $iter = $model->append;
    $model->set($iter, 0, 'FOO');
  my $i = $model->get_iter_first();
  $i = $model->remove($i);
}

sub clear_missps{
  my $self = shift;
  my $tv = $self->_missp_view;
  my $model = $tv->get_model;
  $model->clear();
}

sub add_missp{
  my ($self,$word) = @_;
  my $tv = $self->_missp_view;
  my $model = $tv->get_model;
  my $i = $model->append;
  $model->set($i, 0, $word);
}

1;

