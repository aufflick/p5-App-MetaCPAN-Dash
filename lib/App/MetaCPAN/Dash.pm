package App::MetaCPAN::Dash;

=head1 NAME

App::MetaCPAN::Dash - The great new App::MetaCPAN::Dash!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use App::MetaCPAN::Dash;

    my $foo = App::MetaCPAN::Dash->new();
    ...

=cut

use Moose;

with 'MooseX::Runnable';
with 'MooseX::Getopt' => {
  getopt_conf => [],
};

use DBI;
use MetaCPAN::Client;
use File::Basename;

has 'outputdir' => (is => 'rw',
                    isa => 'Str',
                    required => 0,
                    documentation => 'Set this to the path of an existing directory to write the docset into. If this is omitted, the docset will be automatically installed into Dash.');

has '_module_name' => (is => 'rw',
                       isa => 'Str');

has '_output_path' => (is => 'rw',
                       lazy => 1,
                       default => sub {
                           my $self = shift;
                           my $name = $self->_module_name;
                           $name =~ s/:://g;
                           $self->outputdir . "/$name.docset";
                       });

has '_base_dir' => (is => 'ro', lazy => 1, default => sub { shift->_output_path . '/Contents/Resources/Documents' });

has '_dbh' => (is => 'ro',
               lazy => 1,
               default => sub {
                   my $db_dir = shift->_output_path . '/Contents/Resources';
                   system("mkdir -p $db_dir") == 0 or die; # TODO: properly
                   DBI->connect("dbi:SQLite:dbname=$db_dir/docSet.dsidx")
                       or die $DBI::errstr;
               });

has '_meta_cpan' => (is => 'ro',
                     lazy => 1,
                     default => sub {
                         MetaCPAN::Client->new( ua_args => [ agent => __PACKAGE__ ]);
                     });

sub run {
    my ($self) = @_;

    $self->usage->die
        unless scalar(@{$self->extra_argv}) == 1;

    $self->_module_name($self->extra_argv->[0]);

    my $install = 0;
    if (!$self->outputdir) {
        $install = 1;
        $self->outputdir("/tmp"); #TODO properly with file::temp and cleanup
    }

    die "The output location " . $self->_output_path . " already exists, will not overwrite\n"
        if -e $self->_output_path;

    mkdir $self->_output_path
        or die $!;

    $self->create_index_db;

    my ($names, $paths, $types) = $self->get_modules;

    $self->store_index_data($names, $paths, $types);

    $self->get_all_docs($names, $paths, $types);

    $self->write_plist;

    if ($install) {
        system("open " . $self->_output_path) == 0
            or die "Could't open in Dash: " . $self->_output_path;
    }
}

sub write_plist {
    my $self = shift;

    #TODO: properly
    open my $fh, '>', $self->_base_dir . "/../../Info.plist"
        or die $!;

    my $name = $self->_module_name;

    print $fh <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIdentifier</key>
	<string>$name</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>DocSetPlatformFamily</key>
	<string>$name</string>
	<key>isDashDocset</key><true/>
    <key>isJavaScriptEnabled</key>
    <true/>
</dict>
</plist>
EOF
}

sub get_all_docs {
    my ($self, $names, $paths, $types) = @_;

    for my $i (0..$#{$names}) {

        my $name = $names->[$i];
        my $path = $paths->[$i];
        my $type = $paths->[$i];

        my $pod = eval { $self->_meta_cpan->pod($name)->html };

        if ( defined($pod) && $pod !~ /^\s+$/ && $name !~ /^_.*/) {
            $self->write_pod($name, $path, $pod);
        } else {
            $self->delete_from_index($name, $path, $type);
        }
    }
}

sub write_pod {
    my ($self, $name, $path, $pod) = @_;

    # Figure out our path depth so we can set the relative link correclty in the html
    my @split_path = split /\//, $path;
    my $depth = scalar @split_path;

    my $dir = dirname $path;

    system("mkdir -p " . $self->_base_dir . "/$dir") == 0 or die; # TODO: properly

    open my $fh, '>', $self->_base_dir . "/$path"
        or die $!;

    warn "writing to " . $self->_base_dir . "/$path";

    print $fh $self->munge_html($depth, $pod, $name);
}

sub munge_html {
    my ($self, $depth, $html, $title) = @_;

        my $path = '../' x $depth;

    my $header = <<"HEADER";
<html>
<head>
  <title>$title</title>
  <link rel="stylesheet" type="text/css" href="${path}style.css" />
  <link rel="stylesheet" href="${path}default.min.css" />
  <script src="${path}highlight.min.js"></script>
</head>
<body>
<script>hljs.initHighlightingOnLoad();</script>
HEADER

    my $footer = <<"FOOTER";
</body>
</html>
FOOTER

    return $header . $html . $footer;
}

sub delete_from_index {
    my ($self, $name, $path, $type) = @_;

    $self->execute_sql(qq{
         DELETE FROM searchIndex WHERE name = ? AND path = ? AND type = ?
},
                       $name,
                       $path,
                       $type);
}

sub get_modules {
    my ($self) = @_;

    my $parent_module = $self->_meta_cpan->module($self->_module_name)
        or die "Failed to get module";
    
    my @module_list = grep { $_->{name} } @{$parent_module->module};

    die "Module has no named children"
        unless scalar(@module_list);

    my (@names, @types, @paths);

    for my $module (@module_list) {
        push @names, $module->{name};
        push @types, 'Package';

        my $path = $module->{name};
        $path =~ s!::!/!g;
        push @paths, "$path/" . $module->{name} . ".html"
    }

    return (\@names, \@paths, \@types);
}

sub store_index_data {
    my ($self, $names, $paths, $types) = @_;

    for my $i (0..$#{$names}) {
        $self->execute_sql(qq{
        INSERT OR IGNORE INTO searchIndex(name, path, type) VALUES (?,?,?);
    },
                           $names->[$i],
                           $paths->[$i],
                           $types->[$i]);
    }
}

sub create_index_db {
    my ($self) = @_;

    $self->execute_sql(q{
        CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
    });

    $self->execute_sql(q{
        CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
    });
}

sub execute_sql {
    my ($self, $sql, @params) = @_;

    my $sth = $self->_dbh->prepare($sql)
        or die "Failed to prepare sql: " . $DBI::errstr;

    $sth->execute(@params)
        or die "Failed to execute sql: " . $DBI::errstr;
}

sub _usage_format {
    return "usage:\n\t%c %o The::Module::Name\n\noptions:";
};

=head1 AUTHOR

Mark Aufflick, C<< <mark at htb.io> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-app-metacpan-dash at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-MetaCPAN-Dash>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Mark Aufflick.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of App::MetaCPAN::Dash
