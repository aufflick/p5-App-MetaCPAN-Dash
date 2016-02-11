use 5.006;
use strict;
use warnings;

use Module::Build::Pluggable qw(
                                   CPANfile
                                   ReadmeMarkdownFromPod
                                   Repository
                               );

my $builder = Module::Build::Pluggable->new(
    module_name         => 'App::MetaCPAN::Dash',
    license             => 'artistic_2',
    dist_author         => q{Mark Aufflick <mark@htb.io>},
    dist_version_from   => 'lib/App/MetaCPAN/Dash.pm',
    release_status      => 'stable',
    add_to_cleanup     => [ 'App-MetaCPAN-Dash-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
