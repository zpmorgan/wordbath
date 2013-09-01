use Test::More tests => 7;
use Modern::Perl;
use XML::LibXML;
use File::Slurp;

use lib 'lib';
use Wordbath::Transcript;

my $example_wbml_path = 't/stuff/example.wbml';
my $output_wbml_path = '/tmp/example_saved.wbml';

my $xmlparser = XML::LibXML->new();

my $schema = XML::LibXML::Schema->new( location => 'assets/wbml.xsd' );
ok ( $schema, 'Good XML::LibXML::Schema was initialised' );

my $doc = $xmlparser->parse_file( $example_wbml_path );
ok($doc);

ok (defined eval { $schema->validate($doc)}, '$schema validates example wbml');
if ($@){
  diag ("VALIDATION ERRORS:");
  diag($@);
}

my $tmodel = Wordbath::Transcript::Model->new(from_wbml => $example_wbml_path);
isa_ok ($tmodel => 'Wordbath::Transcript::Model');
is(
  $tmodel->current_text,
  "[beep]\n\nBarack: [coughs]FOO.",
  'loaded wbml vs text');

$tmodel->save_wbml($output_wbml_path);
ok (-e $output_wbml_path, 'spewed wbml file exists.');

use Test::XML::Compare;
my $out_wbml = $tmodel->to_wbml;
diag($@)
 unless is_xml_same (read_file($example_wbml_path), $out_wbml, 'compare xml, input vs output');


