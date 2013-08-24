package Wordbath::Roles::Logger;
use Moose::Role;
use Log::Fast;
has logger => (is => 'ro', isa => 'Log::Fast', default => sub{Log::Fast->global()});
1;
