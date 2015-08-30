use Test::More tests => 13;
use Modern::Perl;
use XML::LibXML;
use Test::XML::Compare;
use Path::Tiny;
use utf8;

use lib 'lib';
use Wordbath::Transcript::Model;

my $xmlparser = XML::LibXML->new();

my $schema = XML::LibXML::Schema->new( location => 'assets/wbml.xsd' );
ok ( $schema, 'Good XML::LibXML::Schema was initialised' );


sub test_wbml{
  my (%args) = @_;
  my $name = $args{name};
  my $output_wbml_path = "/tmp/${name}_saved.wbml";
  my $doc;
  if ($args{wbml_path}){
    $doc = $xmlparser->parse_file( $args{wbml_path});
  } else {
    $doc = $xmlparser->parse_string( $args{wbml});
  }

  ok (defined eval { $schema->validate($doc)}, "case $args{name}: schema validates example wbml");
  if ($@){
    diag ("VALIDATION ERRORS:");
    diag($@);
  }

  my $tmodel;
  if ($args{wbml_path}){
    $tmodel = Wordbath::Transcript::Model->new(from_wbml_file => $args{wbml_path});
  } else {
    $tmodel = Wordbath::Transcript::Model->new(from_wbml => $args{wbml});
  }
  isa_ok ($tmodel => 'Wordbath::Transcript::Model');
  is( $tmodel->current_text, $args{target_text}, "case $name: text comparison");

  my $in = $args{wbml} // path($args{wbml_path})->slurp_utf8;
  my $out = $tmodel->to_wbml;
  my $xml_same = is_xml_same ($in, $out, "compare xml, input vs output: case $name ");
  unless($xml_same){
    warn;
    diag($@);
    my $out_file = "/tmp/$name.wbml";
    path($out_file)->spew_utf8($tmodel->to_wbml);
    diag("SPEWED OUTPUT TO $out_file");
  }
}

#basic speakers, events, paragraphs.
test_wbml(
  name => 'example',
  wbml_path => 't/stuff/example.wbml',
  target_text => 
    "[beep]\n\nBarack Obama: [coughs]FOO.",
);
# test alignment vectors
test_wbml(
  name => 'vectors',
  wbml_path => 't/stuff/example_vectors.wbml',
  target_text =>
    "Karl: Hi.\n\n[beep]\n\nHelmut: Hello.",
);

# test unicode.
# also test varying line spacing.
# also test more of speaker labeling.
test_wbml(
  name => 'unicode',
  wbml => <<'WBML',
<?xml version="1.0" encoding="UTF-8"?>
<transcript>
  <speaker id="Barack" label="Barack" first-label="Barack Obama"/>
  <speaker id="McCain" label="John McCain"/>
  <speakerless-event>嘟</speakerless-event>
  <p speaker="Barack">I just heard a 嘟!</p>
  <p speaker="McCain"><speaker-event>嘟</speaker-event> Ow!</p>
  <p speaker="Barack">My opponent just 嘟'd!</p>
</transcript>
WBML
  target_text =>
    "[嘟]\n\nBarack Obama: I just heard a 嘟!\n\n" .
    "John McCain: [嘟] Ow!\n\nBarack: My opponent just 嘟'd!"
);



