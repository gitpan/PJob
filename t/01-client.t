use strict;
use warnings;

use Test::More tests => 5;                      # last test to print
use PJob::Client;

my $pc = PJob::Client->new(server => 'localhost:10086');
isa_ok($pc,'PJob::Client');
is($pc->{_queued},0,'not queued');

my ($server,$port) = $pc->_get_remote;
is($port,10086,'port is 10086');

$pc->port(32800);
($server,$port) = $pc->_get_remote;
is($port,32800,'port is 32800');

$pc->queue_command('ls','ps')->queue_command('df');
is(scalar @{$pc->_cqueue},3,'queued 3 commands');
