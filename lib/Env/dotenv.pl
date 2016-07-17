#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw(GetOptionsFromArray);

GetOptionsFromArray(
	\@ARGV,
	'f|env-file=s@'	=> \my @env_files,
);

my $source_builtin = 'source';

die "Usage: $0 [-f ENV_FILE] [-f ENV_FILE] PROG [ARG1 ARG2 ...]" unless scalar @ARGV;

pipe my ($reader, $writer )
	or die "Error in pipe: $!";

# Parent
if ( my $pid = fork ) {
	# Defer import until we're in the parent
	require Storable;
	Storable->import('fd_retrieve');

	# Close the writer side of the pipe; all we're doing is reading.
	close $writer or die "Error in close: $!";

	# Read the child's %ENV into a hash
	my %child_env = %{fd_retrieve($reader)};
	close($reader);

	require Data::Dumper;

	delete $ENV{LS_COLORS};
	@ENV{keys %child_env} = values %child_env;

	exec @ARGV;
}
# Child
else {
	close $reader or die "Error in close: $!";

	# Open STDOUT to pipe
	close STDOUT or die "Error in close: $!";
	open STDOUT,, '>&', $writer or die "Error in open: $!";

	# exec the shell
	exec <<__PROG__;
		$source_builtin @env_files
		exec $^X -MStorable=store_fd -e 'store_fd \\%ENV, \\*STDOUT'
__PROG__
}
