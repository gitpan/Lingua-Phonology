#!/usr/bin/perl

package Lingua::Phonology::Boundary;

=head1 NAME

Lingua::Phonology::Boundary

=head1 SYNOPSIS

=head1 DESCRIPTION

This module is strictly for internal use by Lingua::Phonology::Rules.

=cut

use strict;
use warnings;
use Lingua::Phonology::Segment;
our @ISA = qw(Lingua::Phonology::Segment);

our $VERSION = 0.1;

# Inherit all methods possible from above. Overwrite only value_ref()

sub value_ref {
	my ($self, $feature) = @_;

	if ($feature eq 'BOUNDARY') {
		return \1;
	}
	else {
		return undef;
	}
}

# Castrate delink(), too
sub delink {}

# Return the truth from all_values
sub all_values {
	return (BOUNDARY => 1);
}

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
