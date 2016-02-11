

on configure => sub {
    requires 'Module::Install::Pluggable';
    requires 'Module::Install::Pluggable::CPANfile';
    requires 'Module::Install::Pluggable::ReadmeMarkdownFromPod';
    requires 'Module::Install::Pluggable::Repository';
};

requires 'MooseX::Runnable';
requires 'MooseX::Getopt';
requires 'Getopt::Long::Descriptive';
requires 'MetaCPAN::Client';
requires 'File::Path';
requires 'DBI';
requires 'DBD::SQLite';
