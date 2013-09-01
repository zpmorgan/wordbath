use Test::More tests => 2;
use Modern::Perl;

use lib 'lib';
use Wordbath::Transcript;

use XML::LibXML;

my $schema = XML::LibXML::Schema->new( location => 'assets/wbml.xsd' );
ok ( $schema, 'Good XML::LibXML::Schema was initialised' );

my $tmodel = Wordbath::Transcript::Model->new(from_wbml => 't/example.wbml');
isa_ok ($tmodel => 'Wordbath::Transcript::Model');
$tmodel->save_wbml('t/example_saved.wbml');


