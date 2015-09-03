package Wordbath::Speller;
use Moose;
use Modern::Perl;
use utf8;
#use Gtk3;

with 'Wordbath::Roles::Whenever';
Wordbath::Roles::Whenever->import();;
signal ('ignoring');

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
  my $scrolledwin = Gtk3::ScrolledWindow->new();
  $scrolledwin->add($self->_missp_view);
  $vb->pack_end($scrolledwin,1,1,0);
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
  #                                    word          stock icon    bg color
  my $model = Gtk3::ListStore->new(qw/Glib::String Glib::String Glib::String/);
  for(qw/1 2 3 4/){
    my $iter = $model->append;
    $model->set($iter, 0, $_);
    $model->set($iter, 1, 'gtk-add');
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
  my $wcolumn = Gtk3::TreeViewColumn->new_with_attributes(werds => $ren_text, 
    text=>0, 'cell-background'=>2);
  $tree->append_column($wcolumn);

  my $ren_ignore = Gtk3::CellRendererPixbuf->new();
  my $icolumn = Gtk3::TreeViewColumn->new_with_attributes(ignore => $ren_ignore);#, pixbuf=>1);
  $icolumn->set_attributes ( $ren_ignore, 'icon-name' => 1);#'gtk-add' );
  $tree->append_column($icolumn);

  $tree->set_grid_lines ('vertical');
  $tree->signal_connect_swapped('row_activated', \&on_row_activated, $self);
  return $tree;
}

sub on_row_activated{
  my ($self, $path, $col, $tv) = @_;
  my $model = $tv->get_model;
  my $i = $model->get_iter($path);
  my $word_txt = $model->get($i, 0);
  $model->set($i, 2,'darkgreen');
  $self->blurp (ignoring => $word_txt);
}

sub clear_missps{
  my $self = shift;
  my $tv = $self->_missp_view;
  my $model = $tv->get_model;
  $model->clear();
}

sub add_missp{
  my ($self,$word) = @_;
  my $txt = $word->text;
  my $tv = $self->_missp_view;
  my $model = $tv->get_model;
  my $i = $model->get_iter_first;
  while(1){
    my $stord_word = $model->get($i,0);
    return if $txt eq $stord_word;
    last unless $model->iter_next($i);
  }
  my $a = $model->append;
  $model->set($a, 0, $txt);
  $model->set($a, 1, 'gtk-add');
}
sub remove_missp{
  my ($self,$word) = @_;
  my $tv = $self->_missp_view;
  my $model = $tv->get_model;
  my $i = $model->get_iter_first;
  while(1){
    my $row_word = $model->get($i,0);
    if ($word eq $row_word){
      $model->remove($i);
      return;
    }
    last unless $model->iter_next($i);
  }
}

1;

