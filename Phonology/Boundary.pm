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
use Lingua::Phonology::RuleSegment;
our @ISA = qw(Lingua::Phonology::RuleSegment);

our $VERSION = 0.2;

# Never have any other feature value
sub value_ref {
	return undef;
}
# Always be a boundary
sub BOUNDARY {
	return 1;
}

# Castrate delink(), too
sub delink {}

# Return the truth from all_values
sub all_values {
	return (BOUNDARY => 1);
}
 1;

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
