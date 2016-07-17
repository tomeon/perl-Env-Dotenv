package Env::Dotenv;

our $VERSION = '0.0.1';

use strict;
use warnings;

use Capture::Tiny qw(capture);
use Carp qw(croak confess);
use Cwd qw(cwd abs_path);
use File::Spec;
use Storable qw(fd_retrieve);

sub import {
    my ( $class, @args ) = @_;

    if ( @args ) {
        my $dotenv = $class->new( @args );
        $dotenv->set_env();
    }

    return;
}

sub new {
    my ( $class, @args ) = @_;

    my %options = (
        'source_builtin'    => ['source'],
        ref $args[$#args] eq 'HASH' ? %{pop @args} : (),
    );

    $options{shell} = $class->_validate_shell( $options{shell} // $ENV{SHELL} // '/bin/bash' );

    push @args, cwd() . '/.env' unless @args;
    @{$options{env_files}} = $class->_validate_env_files( @args );

    return bless \%options, $class;
}

sub shell {
    my ( $self, $maybe_shell ) = @_;
    $self->{shell} = $self->_validate_shell( $maybe_shell ) if $maybe_shell;
    return $self->{shell};
}

sub source_builtin {
    my ( $self, @maybe_source_builtin ) = @_;
    @{$self->{source_builtin}} = @maybe_source_builtin if @maybe_source_builtin;
    return @{$self->{source_builtin}};
}

sub env_files {
    my ( $self, @maybe_env_files ) = @_;
    @{$self->{env_files}} = $self->_validate_env_files( @maybe_env_files ) if @maybe_env_files;
    return @{$self->{env_files}};
}

sub set_env {
    my ( $self, @env_files ) = @_;
    my %child_env = $self->get_env( @env_files );
    @ENV{keys %child_env} = values %child_env;
    return %ENV if wantarray;
}

sub get_env {
    my ( $self, @env_files ) = @_;

    @env_files = @{$self->{env_files}} unless @env_files;
    croak "No environment files provided" unless @env_files;

    pipe my ( $reader, $writer )
        or die "Error in pipe: $!";

    my @source_builtin = ref $self->{source_builtin} eq 'ARRAY'
        ? @{$self->{source_builtin}}
        : $self->{source_builtin};

    my $source_cmd = qq{ @source_builtin @{$self->{env_files}} };
    my $storable_cmd = q{perl -MStorable=store_fd -C0 -e 'use strict; use warnings; store_fd \\%ENV, \\*STDOUT or die "Failed to store %ENV"'};

    my ( $stdout, $stderr, $exit ) = eval {
        capture {
            system $self->{shell}, q{-c}, qq{ $source_cmd && $storable_cmd };
        };
    };

    croak $@ if $@;

    if ( $exit ) {
        print STDERR $stderr;
        exit $exit;
    }

    _open(my $stdout_fh, '<', \$stdout);

    my $child_env_hashref = fd_retrieve($stdout_fh);

    croak "Error retrieving %ENV" unless defined $child_env_hashref;

    return %{$child_env_hashref};
}

#
# Class methods
#
sub _validate_shell {
    my ( $class, $shell ) = @_;

    my $shell_abs_path = abs_path( $shell );

    croak "No such file: $shell" unless -e $shell_abs_path;
    croak "Not an executable: $shell" unless -x _;

    return $shell_abs_path;
}

sub _validate_env_files {
    my ( $class, @env_files ) = @_;

    my @validated_env_files;
    foreach my $env_file ( @env_files ) {
        croak "No such file: $env_file" unless -e $env_file;
        croak "Not readable: $env_file" unless -e _;
        push @validated_env_files, $env_file;
    }

    return @validated_env_files;
}

#
# Wrapper methods
#
sub _pipe ($$) {
    pipe( $_[0], $_[1] ) or confess sprintf q{Error from pipe(%s): %s},
        join(q{, }, @_), $!;
}

sub _fork () {
    my $pid = fork;
    die "Error from fork(): $!" unless defined $pid;
    return $pid;
}

sub _open ($$;@) {
    open($_[0], $_[1], @_[2..$#_])
        or confess sprintf q{Error from open(%s): %s},
            join(q{, }, @_), $!;
}

sub _close ($) {
    close $_[0] or confess sprintf q{Error from close(%s): %s},
        join(q{, }, @_), $!;
}

1;

__END__

=head1 NAME

Env::Dotenv

=head1 SYNOPSIS


=head1 FUNCTIONS

=cut
