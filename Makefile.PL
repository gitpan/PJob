
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  DISTNAME  => 'PJob',
  NAME      => 'PJob',
  AUTHOR    => "woosley\.xu",
  ABSTRACT  => "POE\ Job\ Server\/Client",
  VERSION   => '0.37',
  EXE_FILES => [ qw() ],
  (eval { ExtUtils::MakeMaker->VERSION(6.31) } ? (LICENSE => 'perl') : ()),
  PREREQ_PM    => {
    "POE::Wheel::Run" => '0',
    "Scalar::Util" => '0',
    "Term::ANSIColor" => '0',
    "POE::Component::Server::TCP" => '0',
    "POE::Component::Client::TCP" => '0',
    "List::Util" => '0',
    "Any::Moose" => '0',
    "POSIX" => '0',
    "List::MoreUtils" => '0',
  },
  test => {TESTS => 't/*.t'}
);

