use Test::More tests => 1;
use Modern::Perl;

use lib 'lib';
use Wordbath::Transcript;

use XML::LibXML;

my $schema = XML::LibXML::Schema->new( location => 'assets/wbml.xsd' );
ok ( $schema, 'Good XML::LibXML::Schema was initialised' );

my $transcript = Wordbath::Transcript->load_wbml('t/example.wbml');
isa_ok ($transcript, 'Wordbath::Transcript');
my $model = Wordbath::Transcript->load_wbml('t/example.wbml');
isa_ok ($model, 'Wordbath::Transcript::Model');
my $transcript->save_wbml('t/example_saved.wbml');


