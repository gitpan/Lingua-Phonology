#!/usr/bin/perl -w

package Lingua::Phonology::PseudoSegment;

=head1 NAME

Lingua::Phonology::PseudoSegment - an internal-use only module for
Lingua::Phonology::Rules, for handling tiers.

=head1 DESCRIPTION

A PseudoSegment object hides multiple Segment objects inside it. It doesn't
do much by itself, as it generally just passes whatever methods are called
on it through to the interior segments.

Explicit methods may be defined for PseudoSegment if the default behavior
isn't desirable for some situations.

=cut

use strict;
use Carp;

our $VERSION = 0.1;

=head1 METHODS

Very few of these are explicitly defined. Most method called on a
PseudoSegment are passed through to the segments it's hiding.

=head2 new

Returns a new PseudoSegment object. Take a list of Segment object as it
arguments.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = [ ];

	return carp "No segments given for pseudo-segment" if not @_;
	push (@$self, @_);
	
	bless ($self, $class);
	return $self;
} # end init

=head2 all_values

Always returns the value C<< ( PSEUDO => 1 ) >>. This is mostly just useful
to help Lingua::Phonology::Rules, so that it doesn't think that
pseudo-segments are blank.

=cut

sub all_values {
	return ( PSEUDO => 1 );
} # end all_values

our $AUTOLOAD;
sub AUTOLOAD {
	my $self = shift;
	my $method = $AUTOLOAD;
	$method =~ s/.*:://;

	# Pass everything through to the segments
	my @return;
	for (@$self) {
		unshift (@return, $_->$method(@_));
	} # end for
	# See if they all agreed
	for my $i (0 .. $#return) {
		no warnings 'uninitialized'; # To avoid warnings when comparing undefs
		return undef if (exists($return[$i + 1]) && $return[$i] ne $return[$i + 1]);
	} # end for

	# If they all agreed, then return that value
	return $return[0];
} # end AUTOLOAD

1;

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
