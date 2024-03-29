package PJob
use strict;
use warnings;

our $VERSION=0.41;
1;
__END__
=pod

=head1 NAME

PJob -- Poe/Perl Job Server and Client

=head1 VERSION

This document describes version 0.41 of PJob

=head1 SYNOPSIS

    $ps = PJob::Server->new(jobs => {ls => 'ls /home', ps => 'ps -aux'})
                      ->run();
    $pc = PJob::Client->new(server =>'localhost:10086')->run();

=head1 DESCRIPTION

PJob::Server is a module built on L<Any::Moose>, L<POE::Wheel::Run> and L<POE::Component::Server::TCP>, it provide you a simple way to setup your own job server.

PJob::Server support some features like allowed_hosts, job_dispatch, max_connections, See L<PJob::Server> for more details.

PJob::Client is a simple client module for PJob::Server

=head1 SEE ALSO

L<PJob::Server>, L<PJob::Client>, L<POE>, L<Any::Moose>

=head1 AUTHOR

woosley.xu<woosley.xu@gmail.com>

=head1 COPYRIGHT & LICENSE

This software is copyright (c) 2009 by woosley.xu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
