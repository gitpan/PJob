use strict;
use warnings;

use Test::More tests => 12;
use PJob::Server;

my $ps = PJob::Server->new(
    max_connections => 10,
    port            => 10086,
    logfile         => './.logfile',
    jobs            => {'ls' => 'ls -l', 'ps' => 'ps -aux'},
    allowed_hosts   => [qw/127.0.0.1 192.168.1.125/],
);

isa_ok($ps, 'PJob::Server', 'is a PJob::Server');
is($ps->max_connections,         10,           'max connection is 10');
is($ps->port,                    10086,        'open port 10086');
is($ps->logfile,                 './.logfile', 'log file is .logfile');
is(scalar @{$ps->allowed_hosts}, 2,            'two hosts allowed here');
is(scalar keys %{$ps->jobs},     2,            'two jobs ready');
is($ps->_dispatched, 0, 'not dispatched');

$ps->add({ping => 'ping localhost'}, 'df', 'fdisk');
is(scalar keys %{$ps->jobs},     5,            'five jobs ready');

$ps->job_dispatch('127.0.0.2' => [qw/ps ls hoop/], '*' => [qw/df fdisk/]);
my $a = [qw/ps ls df fdisk/];
is_deeply($ps->job_table->{'127.0.0.2'}, $a, 'job table is expected');

$ps->_append_jobs;
is_deeply($ps->job_table->{'192.168.1.125'}, [qw/df fdisk/], 'job table is expected');

is($ps->_dispatched, 1, 'dispatched');

$ps->_log_redirect;
$a = -e $ps->logfile;
is($a, 1, 'log file found');
unlink $ps->logfile;
