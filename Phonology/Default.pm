#!/usr/bin/perl -w

package Lingua::Phonology::Default;

=head1 NAME

Lingua::Phonology::Default - provides access to defaults for other
Lingua::Phonology modules.

=head1 DESCRIPTION

Lingua::Phonology::Default is used internally by several other
Lingua::Phonology modules to provide OS-independent access to default
configuration files.

=cut

use strict;
use warnings;
use Carp;
use File::Basename;
use File::Spec::Functions;
require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/open_default/;

our $VERSION = 0.1;

=head1 FUNCTIONS

=head2 open_default

Opens a default file in the same directory that Lingua::Phonology::* is
installed to. Takes one argument, the "suffix" for the default file.
Default files should be named in the format 'default.*', where the star is
replaced by the suffix.

This function is exported by default.

=cut

sub open_default {
	my $filename = 'default.' . shift;
	open my($fh), catfile(dirname(__FILE__), $filename) or return carp "Couldn't open $filename: $!";
	return $fh;
} # end sub

1;

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
