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

our $VERSION = 0.11;

=head1 FUNCTIONS

=head2 open

Opens a default file in the same directory that Lingua::Phonology::* is
installed to. Takes one argument, the "suffix" for the default file.
Default files should be named in the format 'default.*', where the star is
replaced by the suffix.

=cut

sub open {
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
