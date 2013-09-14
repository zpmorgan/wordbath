use Modern::Perl;
use Test::More tests => 8;
use Test::Number::Delta within => 4*10**9;
# 'epsilon' of 4 billion.

use lib 'lib';
use Wordbath::Transcript::Model;

my $model = Wordbath::Transcript::Model->new(from_wbml_file => 't/stuff/blurb.ogg.wbml');

sub test_alignment {
  my %args = @_;
  my $pattern = $args{pattern};
  my $pos_ns = $args{pos_sec} * 10**9;
  my ($i,$e) = $model->find_text($pattern);
  my $guess_ns = $model->audiosync->audio_pos_ns_at($i);
  delta_ok ( $pos_ns, $guess_ns, "guessed position for '$pattern'".
    "\n  $pos_ns :: $guess_ns" );
}

test_alignment( pattern => 'Please transc', pos_sec => 26.034);
test_alignment( pattern => 'is best edito', pos_sec => 34.528);
test_alignment( pattern => 'I\'m Katu, an', pos_sec => 36.074);
test_alignment( pattern => 'means that yo', pos_sec => 13.101);
test_alignment( pattern => 'You are using', pos_sec => 02.235);
test_alignment( pattern => 'and it offers', pos_sec => 06.596);
test_alignment( pattern => 'several techn', pos_sec => 19.682);
test_alignment( pattern => 'Perl, GStream', pos_sec => 21.595);


