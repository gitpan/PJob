package PJob::Client;
our $VERSION = '0.17';



use Any::Moose;
use Term::ANSIColor;
use Carp qw/carp croak/;
use POE qw/Component::Client::TCP/;

$| = 1;
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

sub run {
    my $self = shift;
    my ($server, $port) = $self->get_remote;
    $self->{_session} = POE::Component::Client::TCP->new(
        RemoteAddress => $server,
        RemotePort    => $port,
        Connected     => sub { $self->_connected(@_) },
        ServerInput   => sub { $self->_get_input(@_) },
        Disconnected  => sub { $self->_disconnected(@_) },
        ServerError   => sub { $self->_server_error(@_) },
    );
    POE::Kernel->run();
    exit;
}

sub get_remote {
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

sub _get_input {
    my $self  = shift;
    my $input = $_[ARG0];
    if ($input eq '.') {
        print ">";
        my $k = <>;
        chomp $k;
        $_[HEAP]{server}->put($k);
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
    my ($oper,$nexit,$sexit) = @_[ARG0,ARG1,ARG2];
    return if $nexit == 0;
    print "Server Error:\n";
    print "\toperation\t$oper\n";
    print "\t   Reason\t$sexit\n";
    $_[KERNEL]->yield('shutdown');
}
1;

__END__
=pod

=head1 NAME
    
    PJob::Client -- Simple PJob client for PJob Server

=head1 SINOPISYS

    $pc =  PJob::Client->new(server => 'localhost',port => '10086')
                       ->run();

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

=back

=head1 TODO
    
B<run_queue>: run a serial of commands

=head1 SEE ALSO
    
    L<POE>,L<Any::Moose>,L<PJob::Server>

=head1 AUTHOR

    woosley.xu<redicaps@gmail.com>

=head1 COPYRIGHT & LICENSE

This software is copyright (c) 2009 by woosley.xu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
