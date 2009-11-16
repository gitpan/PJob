package PJob::Server;
our $VERSION = '0.19';


our $ALIAS = "POE JOB SERVER, Version: $VERSION";

use Any::Moose;
use Data::Dumper;
use POSIX qw/strftime/;
use Scalar::Util qw/reftype/;
use List::Util qw/first/;
use List::MoreUtils qw/uniq/;
use POE qw/Component::Server::TCP Wheel::Run/;
#use Smart::Comments;
use constant {
    OUTPUT    => 'Out',
    ERROR     => 'Err',
    NOSUCHJOB => 'No Such A Job',
    NOMORECON => 'Sorry, no more connection on this server',
    NOTALLOWD => 'Sorry, you are not allowed on this server',
    NOCLIEJOB => 'Sorry, no job found for you on this server',
};

has 'jobs' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

has 'port' => (
    is      => 'rw',
    isa     => 'Int',
    default => '32080',
);

has 'logfile' => (
    is  => 'rw',
    isa => 'Str',
);

has 'log_commands' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has 'job_table' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

has '_dispatched' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

has '_pid' => (
    is      => 'rw',
    default => sub { {} },
);

has 'allowed_hosts' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has 'max_connections' => (
    is      => 'rw',
    isa     => 'Int',
    default => '-1',
);

# add programs to the job server
sub add() {
    my ($self, @programs) = @_;

    foreach my $p (@programs) {
        if (reftype $p && reftype $p eq 'HASH') {
            $self->jobs({%{$self->jobs}, %{$p}});
            next;
        }
        elsif (!reftype $p) {
            $self->jobs({%{$self->jobs}, $p => $p});
        }
    }
    return $self;
}

# run the job server
sub run {
    my $self = shift;

    $self->_check_jobs;
    $self->_append_jobs;
    $self->_log_redirect;
    $self->{_clients} = 0;
    $self->{_session} = POE::Component::Server::TCP->new(
        Alias              => $ALIAS,
        Port               => $self->port,
        ClientInput        => sub { $self->_spawn(@_) },
        ClientConnected    => sub { $self->_client_connect(@_) },
        ClientDisconnected => sub { $self->_client_disconnected(@_) },
        InlineStates       => {
            job_stdout => sub { $self->send_to_client(OUTPUT, @_) },
            job_stderr => sub { $self->send_to_client(ERROR,  @_) },
            job_close  => sub { $self->_close(@_) },
            job_signal => sub { $self->_sigchld(@_) },
            usage      => sub { $self->_usage(@_) },
        }
    );
    $self->log(*STDOUT, "Started $ALIAS at Port: " . $self->port . "\n");
    POE::Kernel->run();
    return $self;
}

# print usage information
sub _usage {
    my $self         = shift;
    my $client       = $_[HEAP]->{client};
    my $remote_ip    = $_[HEAP]->{remote_ip};
    my $allowed_jobs = $self->job_table->{$remote_ip};

    my $usage_str;
    if ($self->_dispatched) {
        if (@{$allowed_jobs}) {
            $usage_str = 'Usage: ' . join ' ', sort @{$allowed_jobs};
        }
        else {
            $usage_str = ERROR . "\t" . NOCLIEJOB;
            $client->put($usage_str);
            $_[KERNEL]->yield("shutdown");
        }
    }
    else {
        $usage_str = 'Usage: ' . join ' ', sort keys %{$self->jobs};
    }
    $client->put($usage_str);
    $client->put('.');
}

# run the program
sub _spawn {
    my $self = shift;
    my ($heap, $input) = @_[HEAP, ARG0];
    my $client      = $heap->{client};
    my $remote_ip   = $heap->{remote_ip};
    my $remote_port = $heap->{remote_port};

    if ($heap->{job}->{$client}) {
        $heap->{job}->{$client}->put($input);
        return;
    }
    if ($input =~ /^quit$/i) {
        $client->put("B'bye!");
        $_[KERNEL]->yield("shutdown");
        return;
    }

    $_[KERNEL]->yield('usage') if $input =~ /^usage$/i;

    my $program;
    if ($self->_dispatched) {
        $program = first { $_ eq $input } $self->job_table->{$remote_ip};
    }
    else {
        $program = $self->jobs->{$input};
    }

    unless (defined $program) {
        $client->put(ERROR . "\t" . NOSUCHJOB);
        $_[KERNEL]->yield("usage");
        return;
    }

    $self->log(*STDOUT, "$remote_ip:$remote_port : $program  \n")
      if $self->log_commands;

    my $kid = POE::Wheel::Run->new(
        Program     => $program,
        StdoutEvent => 'job_stdout',
        StderrEvent => 'job_stderr',
        CloseEvent  => 'job_close',
    );

    $heap->{job}->{$client} = $kid;

    #just the program is enough right now. Feature can be added if necessary
    $self->_pid->{$kid->PID} = $program;
    $_[KERNEL]->sig_child($kid->PID, "job_signal");
    $client->put("Job $program :::" . $kid->PID . " started.");
}

sub send_to_client {
### @_ : @_
    my $self = shift;
    my $mark = shift;

    $_[HEAP]->{client}->put($mark . "\t" . $_[ARG0]);
}

# not sure if it is needed
sub error_event {
    my $self = shift;

#    my($oper,$errno,$errmsg) = @_[ARG0,ARG1,ARG2];
#    $_[HEAP]->{client}->put("Error: $oper failed, message-- $errmsg");
}

sub _sigchld {
    my $self = shift;
    my ($pid, $exit) = @_[ARG1, ARG2];
    my $program = $self->_pid->{$pid};

    if ($exit != 0) {
        $exit >>= 8;
    }
    $_[HEAP]->{client}->put("Job $program :::$pid exited with status $exit");
    $_[HEAP]->{client}->put('.');
    delete $_[HEAP]->{job}->{$_[HEAP]->{client}};
    delete $self->_pid->{$pid};
}

# not sure we need this or not
sub _close {

#    my $self = shift;
#    delete $_[HEAP]->{job};
}

# open log file and redirect stdout/stdin to it
sub _log_redirect {
    my $self = shift;

    if ($self->logfile) {
        open STDOUT, '>>', $self->logfile or die $!;
        open STDERR, ">&STDOUT" or die $!;
    }
}

sub _client_connect {
    my $self = shift;
    my ($kernel, $heap) = @_[KERNEL, HEAP];

    my $remote_ip   = $heap->{remote_ip};
    my $remote_port = $heap->{remote_port};
    my $allow_hosts = $self->allowed_hosts;

    # reached max connection
    if ($self->max_connections > 0) {
        if ($self->{_clients} >= $self->max_connections) {
            $self->send_to_client(ERROR, NOMORECON);

#            $heap->{client}->put("No more connections on this server");
            $kernel->yield('shutdown');
            return;
        }
    }
    $self->{_clients}++;

    # not allowed on this server
    if (@{$allow_hosts} || $self->_dispatched) {
        if (!first { $remote_ip eq $_ } @{$allow_hosts},
            keys %{$self->job_table})
        {
            $heap->{client}->put(ERROR . "\t" . NOTALLOWD);
            $kernel->yield('shutdown');
            return;
        }
    }

    # allowed server
    $kernel->yield('usage');
    $self->log(*STDOUT,
        "CONNECTION FROM ${remote_ip}:${remote_port} ESTABLISHED\n");
}

sub _client_disconnected {
    my $self        = shift;
    my $remote_ip   = $_[HEAP]->{remote_ip};
    my $remote_port = $_[HEAP]->{remote_port};

    $self->log(*STDERR, "DISCONNECTED FORM ${remote_ip}:${remote_port} \n");
    $self->{_clients}--;
}

sub log {
    my $self = shift;
    my ($fh, $output) = @_;
    chomp $output;

    return unless $output;
    my $now = strftime "%y/%m/%d %H:%M:%S", localtime;
    print $fh "$now\t$output\n";
}

sub job_dispatch {
    my ($self, %table) = @_;

    $self->_dispatched(1);
    foreach my $host (keys %table) {
        foreach (@{$table{$host}}) {
            if (reftype $_ && reftype $_ eq 'HASH') {
                $self->add($_);
                push @{$self->job_table->{$host}}, keys %$_;
                next;
            }
            elsif (!reftype $_) {
                if (exists ${$self->jobs}{$_}) {
                    push @{$self->job_table->{$host}}, $_;
                }
                else {
                    $self->log(*STDERR, "no program '$_' found in the jobs");
                }
            }
        }
    }

    my $comm_jobs = $self->job_table->{'*'};
    return unless $comm_jobs;

    foreach my $key (keys %{$self->job_table}) {
        my @all = uniq @{$self->job_table->{$key}}, @{$comm_jobs};
        $self->job_table->{$key} = [@all];
    }
}

# Called before start the server. Dispatch the jobs for $self->allowed_hosts
sub _append_jobs {
    my $self      = shift;
    my $comm_jobs = delete $self->job_table->{'*'};
    foreach my $host (@{$self->allowed_hosts}) {
        my @all = uniq @{$self->job_table->{$host}}, @{$comm_jobs};
        $self->job_table->{$host} = [@all];
    }

}

sub _check_jobs {
    my $self = shift;
    if(my $c = first { $_ =~ /^usage|quit$/i } keys %{$self->jobs}){
        $self->log(*STDERR, "'$c' is defined by default, choose another one");
        exit 1;
    }
}

sub _ {
    my $output = shift;
    $output = '\.' if $output =~ /^\.$/;
    return $output;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__

=pod

=head1 NAME

PJob::Server --- Simple POE Job Server 

=head1 SINOPISYS

    use PJob::Server;
    my $server = PJob::Server->new(port => '10086');
    $server->logfile('./.logfile');
    $server->log_commands(1);
    $server->add({ls => 'ls ~/', run => 'perl ~/test.pl'},'ls');
    $server->run();

=head1 DESCRIPTION
    
PJob::Server is a simple POE Job Server module, it provide you some api to write a job server very quickly.

=over 

=item B<new>

Create a PJob::Server object. The available arguments are:
    
    port            : port to listen. 32800 by default
    jobs            : available programs
    logfile         : log file name
    log_commands    : log the command runed by the client
    allowed_hosts   : hosts' ip that are allowed to run job on this server
    max_connections : default is set to -1, means no limit

=item B<add>

add some programs, it receive both hashref and scalar. The key of the hashref is alias of the program. when scalar, the alias and the program have the same value.

=item B<job_dispatch>

    $ser->job_dispatch('127.0.0.1' => [qw/ls ps/,{cat => 'cat file'}], '*' => ['pwd']);
    
Dispatch available job to clients, receive client ip and its job table. * means common jobs which can be dispatched to all clients. Job table should be a arrayref. Jobs must be defined by $self->add except the situation that the element is a hashref, at this time, $self->add is called to add new job. 

Any hosts dispatched with job_dispatch is considered to be an allowed host.

=item B<run>

run the server, no argument needed.

=item B<quit/usage>

Use 'quit' to disconnect with the server. Use 'usage' to get avaiable commands

=back

=head1 SEE ALSO
    
L<PJob::Client>,L<POE::Component::Server::TCP>,L<POE::Wheel::Run>,L<Any::Moose>

=head1 AUTHOR

woosley.xu<woosley.xu@gmail.com>

=head1 COPYRIGHT & LICENSE

This software is copyright (c) 2009 by woosley.xu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
