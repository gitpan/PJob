use strict;
use warnings;

use Test::More tests => 3;                      # last test to print
use PJob::Client;

my $pc = PJob::Client->new(server => 'localhost:10086');
isa_ok($pc,'PJob::Client');
my ($server,$port) = $pc->_get_remote;
is($port,10086,'port is 10086');
is($pc->{_queued},0,'not queued');
