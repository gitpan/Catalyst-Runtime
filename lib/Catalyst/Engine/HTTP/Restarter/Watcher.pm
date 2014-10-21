package Catalyst::Engine::HTTP::Restarter::Watcher;

use Moose;
with 'MooseX::Emulate::Class::Accessor::Fast';

use File::Find;
use File::Modified;
use File::Spec;
use Time::HiRes qw/sleep/;
use Moose::Util qw/find_meta/;
use namespace::clean -except => 'meta';

BEGIN {
    # If we can detect stash changes, then we do magic
    # to make their metaclass mutable (if they have one)
    # so that restarting works as expected.
    eval { require B::Hooks::OP::Check::StashChange; };
    *DETECT_PACKAGE_COMPILATION = $@
        ? sub () { 0 }
        : sub () { 1 }
}

has delay => (is => 'rw');
has regex => (is => 'rw');
has modified => (is => 'rw');
has directory => (is => 'rw');
has watch_list => (is => 'rw');
has follow_symlinks => (is => 'rw');

sub BUILD {
    shift->_init;
}

sub _init {
    my $self = shift;

    my $watch_list = $self->_index_directory;
    $self->watch_list($watch_list);

    $self->modified(
        File::Modified->new(
            method => 'mtime',
            files  => [ keys %{$watch_list} ],
        )
    );
}

sub watch {
    my $self = shift;

    my @changes;
    my @changed_files;
    
    my $delay = ( defined $self->delay ) ? $self->delay : 1;

    sleep $delay if $delay > 0;

    eval { @changes = $self->modified->changed };
    if ($@) {

        # File::Modified will die if a file is deleted.
        my ($deleted_file) = $@ =~ /stat '(.+)'/;
        push @changed_files, $deleted_file || 'unknown file';
    }

    if (@changes) {

        # update all mtime information
        $self->modified->update;

        # check if any files were changed
        @changed_files = grep { -f $_ } @changes;

        # Check if only directories were changed.  This means
        # a new file was created.
        unless (@changed_files) {

            # re-index to find new files
            my $new_watch = $self->_index_directory;

            # look through the new list for new files
            my $old_watch = $self->watch_list;
            @changed_files = grep { !defined $old_watch->{$_} }
              keys %{$new_watch};

            return unless @changed_files;
        }

        # Test modified pm's
        for my $file (@changed_files) {
            next unless $file =~ /\.pm$/;
            if ( my $error = $self->_test($file) ) {
                print STDERR qq/File "$file" modified, not restarting\n\n/;
                print STDERR '*' x 80, "\n";
                print STDERR $error;
                print STDERR '*' x 80, "\n";
                return;
            }
        }
    }

    return @changed_files;
}

sub _index_directory {
    my $self = shift;

    my $dir   = $self->directory;
    die "No directory specified" if !$dir or ref($dir) && !@{$dir};

    my $regex = $self->regex     || '\.pm$';
    my %list;

    finddepth(
        {
            wanted => sub {
                my $file = File::Spec->rel2abs($File::Find::name);
                return unless $file =~ /$regex/;
                return unless -f $file;
                $file =~ s{/script/..}{};
                $list{$file} = 1;

                # also watch the directory for changes
                my $cur_dir = File::Spec->rel2abs($File::Find::dir);
                $cur_dir =~ s{/script/..}{};
                $list{$cur_dir} = 1;
            },
            follow_fast => $self->follow_symlinks ? 1 : 0,
            no_chdir => 1
        },
        ref $dir eq 'ARRAY' ? @{$dir} : $dir
    );
    return \%list;
}

sub _test {
    my ( $self, $file ) = @_;

    my $id;
    if (DETECT_PACKAGE_COMPILATION) {
        $id = B::Hooks::OP::Check::StashChange::register(sub {
            my ($new, $old) = @_;
            my $meta = find_meta($new);
            if ($meta) { # A little paranoia here - Moose::Meta::Role has neither of these methods.
                my $is_immutable = $meta->can('is_immutable');
                my $make_mutable = $meta->can('make_mutable');
                $meta->$make_mutable() if $is_immutable && $make_mutable && $meta->$is_immutable();
            }
        });
    }

    delete $INC{$file}; # Remove from %INC so it will reload
    local $SIG{__WARN__} = sub { };

    open my $olderr, '>&STDERR';
    open STDERR, '>', File::Spec->devnull;
    eval "require '$file'";
    open STDERR, '>&', $olderr;

    B::Hooks::OP::Check::StashChange::unregister($id) if $id;

    return ($@) ? $@ : 0;
}

1;
__END__

=head1 NAME

Catalyst::Engine::HTTP::Restarter::Watcher - Watch for changed application
files

=head1 SYNOPSIS

    my $watcher = Catalyst::Engine::HTTP::Restarter::Watcher->new(
        directory => '/path/to/MyApp',
        regex     => '\.yml$|\.yaml$|\.conf|\.pm$',
        delay     => 1,
    );
    
    while (1) {
        my @changed_files = $watcher->watch();
    }

=head1 DESCRIPTION

This class monitors a directory of files for changes made to any file
matching a regular expression.  It correctly handles new files added to the
application as well as files that are deleted.

=head1 METHODS

=head2 new ( directory => $path [, regex => $regex, delay => $delay ] )

Creates a new Watcher object.

=head2 watch

Returns a list of files that have been added, deleted, or changed since the
last time watch was called.

=head2 DETECT_PACKAGE_COMPILATION

Returns true if L<B::Hooks::OP::Check::StashChange> is installed and
can be used to detect when files are compiled. This is used internally
to make the L<Moose> metaclass of any class being reloaded immutable.

If L<B::Hooks::OP::Check::StashChange> is not installed, then the
restarter makes all application components immutable. This covers the
simple case, but is less useful if you're using Moose in components
outside Catalyst's namespaces, but inside your application directory.

=head1 SEE ALSO

L<Catalyst>, L<Catalyst::Engine::HTTP::Restarter>, L<File::Modified>

=head1 AUTHORS

Catalyst Contributors, see Catalyst.pm

=head1 THANKS

Many parts are ripped out of C<HTTP::Server::Simple> by Jesse Vincent.

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
