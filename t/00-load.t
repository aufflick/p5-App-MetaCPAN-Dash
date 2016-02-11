#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'App::MetaCPAN::Dash' ) || print "Bail out!\n";
}

diag( "Testing App::MetaCPAN::Dash $App::MetaCPAN::Dash::VERSION, Perl $], $^X" );
