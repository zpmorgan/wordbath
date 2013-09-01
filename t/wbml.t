use Test::More tests => 4;
use Modern::Perl;
use XML::LibXML;

use lib 'lib';
use Wordbath::Transcript;

my $example_wbml_path = 't/stuff/example.wbml';

my $xmlparser = XML::LibXML->new();

my $schema = XML::LibXML::Schema->new( location => 'assets/wbml.xsd' );
ok ( $schema, 'Good XML::LibXML::Schema was initialised' );

my $doc = $xmlparser->parse_file( $example_wbml_path );
ok($doc);

ok (0 == eval { $schema->validate($doc)}, '$schema validates example wbml');
if ($@){
  diag ("VALIDATION ERRORS:");
  diag($@);
}

my $tmodel = Wordbath::Transcript::Model->new(from_wbml => $example_wbml_path);
isa_ok ($tmodel => 'Wordbath::Transcript::Model');
$tmodel->save_wbml('/tmp/example_saved.wbml');


