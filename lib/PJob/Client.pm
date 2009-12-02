package PJob::Client;
our $VERSION = '0.37';

use Any::Moose;
use Term::ANSIColor qw/:constants/;
use Carp qw/carp croak/;
use POE qw/Component::Client::TCP/;

$| = 1;
my $yellow = YELLOW;
my $bold   = BOLD;
my $red    = RED;
my $blue   = BLUE;
my $reset  = RESET;
my $green  = GREEN;

has 'server' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has 'port' => (
    is  => 'rw',
    isa => 'Int',
);

has 'job' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
);

has '_cqueue' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
);

sub BUILD {
    my $self = shift;
    $self->{_queued} = 0;
}

sub run {
    shift->_run;
}

sub run_queue {
    my $self = shift;
    $self->{_queued} = 1;
    $self->_run;
}

sub queue_command {
    my $self = shift;
    push @{$self->_cqueue}, @_;
    return $self;
}

sub _run {
    my $self = shift;
    my $sub_for_input = sub { $self->_get_input_interactive(@_) };
    $sub_for_input = sub { $self->_get_input_queue(@_) }
      if $self->{_queued};
    my ($server, $port) = $self->_get_remote;
    $self->{_session} = POE::Component::Client::TCP->new(
        RemoteAddress => $server,
        RemotePort    => $port,
        Connected     => sub { $self->_connected(@_) },
        Disconnected  => sub { $self->_disconnected(@_) },
        ServerError   => sub { $self->_server_error(@_) },
        ServerInput   => $sub_for_input,
    );
    POE::Kernel->run();
    return $self;
}

sub _get_remote {
    my $self = shift;

    my ($server, $port) = split ':', $self->server, 2;

    if (!$self->port) {
        carp "no port specified\n" if !$port;
        $self->port($port);
    }
    return ($server, $self->port);
}

sub _connected {
    my $self = shift;
    my ($peer_addr, $peer_port) = @_[ARG1, ARG2];
    print "Connected at ${peer_addr}:${peer_port}\n";
}

sub _get_input_interactive {
    my $self  = shift;
    my $input = $_[ARG0];
    if ($input eq '.') {
        print _($bold, $yellow, ">");
        my $k = <>;
        chomp $k;
        $_[HEAP]{server}->put($k);
    }
    else {
        $self->_format_and_output($input);
    }
}

sub _get_input_queue {
    my $self = shift;
    my ($input, $heap) = @_[ARG0, HEAP];
    if ($input eq '.') {
        if (!scalar @{$self->_cqueue}) {
            $heap->{server}->put('quit');
            return;
        }
        my $command = shift @{$self->_cqueue};
        chomp $command;
        return unless $command;
        $heap->{server}->put($command);
    }
    else {
        print $input, "\n";
    }
}

sub _disconnected {
    my $self = shift;

    print "Server Disconnected, shutting down.....\n";
    $_[KERNEL]->yield('shutdown');
}

sub _server_error {
    my $self = shift;
    my ($oper, $nexit, $sexit) = @_[ARG0, ARG1, ARG2];
    return if $nexit == 0;
    print "Server Error:\n";
    print "\toperation\t$oper\n";
    print "\t   Reason\t$sexit\n";
    $_[KERNEL]->yield('shutdown');
}

sub _ {
    push @_, $reset;
    return @_;
}

sub _format_and_output {
    my ($self, $input) = @_;
    if ($input =~ /^Usage:(.*)$/) {
        print _("Usage:", $bold, $blue, $1, "\n");
        return;
    }
    elsif ($input =~ /^Job\s+(.*?)\s+:::(\d+)\sstarted\.$/) {
        print _("Job ", $bold, $green, $1, ' :::', $2, $reset, " started\n");
        return;
    }
    elsif ($input =~ /Out\t(.*)$/) {
        print _($1, "\n");
        return;
    }
    elsif ($input =~ /Err\t(.*)$/) {
        print _($yellow, '[stderr] ', $reset, $1, "\n");
        return;
    }
    elsif ($input =~ /^Job\s+(.*?)\s+:::(\d+)(.*?)(\d+)$/) {
        print _(
            "Job ", $bold, $green, $1,    ' :::', $2,
            $reset, $3,    $red,   $bold, $4,     "\n"
        );
        return;
    }
    else {
        print $input, "\n";
    }
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 NAME
    
PJob::Client -- Simple PJob client for PJob Server

=head1 VERSION

This document describes version 0.37 of PJob::Client

=head1 SYNOPSIS

    $pc =  PJob::Client->new(server => 'localhost',port => '10086')
                       ->run();
    $pc =  PJob::Client->new(server => 'localhost:10086')
            ->queue_command('ls','ps')->run_queue;

=head1 DESCRIPTION

PJob::Client is the client for PJob::Server

=over

=item B<server>

    $pc->server('localhost:10086');
    $pc->server('localhost');

=item B<port>
    
    $pc->port('10086');

This method will overwrite the port specified by B<server>

=item B<run>
    
run a interative client

=item B<queue_command>

queue some commands into the command queue

=item B<run_queue>

run the commands in the queue

=back

=head1 SEE ALSO
    
L<POE::Component::Client::TCP>,L<Any::Moose>,L<PJob::Server>

=head1 AUTHOR

woosley.xu<woosley.xu@gmail.com>

=head1 COPYRIGHT & LICENSE

This software is copyright (c) 2009 by woosley.xu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
