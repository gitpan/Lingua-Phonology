#!/usr/bin/perl

package Lingua::Phonology::Functions;

=head1 NAME

Lingua::Phonology::Functions

=head1 SYNOPSIS

	use Lingua::Phonology;
	use Lingua::Phonology::Functions qw/:all/;

=head1 DESCRIPTION

Lingua::Phonology::Functions contains a suite of functions that can be
exported to make it easier to write linguistic rules. I hope to have a
function here for each broad, sufficiently common linguistic process. So if
there are any missing here that you think should be included, feel free to
contact the author.

=cut

use strict;
use warnings::register;
use Carp;
use Lingua::Phonology; # just to get the warning definitions

require Exporter;
our @ISA = qw/Exporter/;

our @EXPORT_OK = qw(
	assimilate
	adjoin
	copy
	dissimilate
	change
	metathesize
	metathesize_feature
	delete_seg
	insert_after
	insert_before
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

our $VERSION = 0.11;


=head1 FUNCTIONS

Lingua::Phonology::Functions does not provide an object-oriented interface
to its functions. You may either call them with their package name
(C<Lingua::Phonology::Functions::assimilate()>), or you may import the
functions you wish to use by providing their names as arguments to C<use>.
You may import all functions with the argument ':all' (as per the Exporter standard).

	Lingua::Phonology::Functions::assimilate();        # If you haven't imported anything
	use Lingua::Phonology::Functions qw(assimilate);   # Import just assimilate()
	use Lingua::Phonology::Functions qw(:all);          # Import all functions

I have tried to keep the order of arguments consistent between all of the
functions. In general, the following hold:

=over 4

=item *

If a feature name is needed for a function, that is the I<first> argument.

=item *

If more than one segment is given as an argument to a function, the first
segment will act upon the second segment. That is, some feature from the
first segment will be assimilated, copied, dissimilated, etc. to the second
segment.

=back

Through these function descriptions, C<$feature> is the name of some
feature in the current Lingua::Phonology::Features object, and
C<$segment1>, C<$segment2> . . . C<$segmentN> are
Lingua::Phonology::Segment objects depending on that same Features object.

=head2 assimilate

	assimilate($feature, $segment1, $segment2);

Assimilates $segment2 to $segment1 on $feature. This does a "deep"
assimilation, copying the reference from $segment1 to $segment2 so that
future modifications of this feature for either segment will be reflected
on both segments. If you don't want this, use C<copy()> instead.

=cut

sub assimilate {
	my ($feature, $seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);
	$seg2->delink($feature);
	$seg2->$feature( $seg1->value_ref($feature) );
	return 1; # return true on success
}

=head2 adjoin

	adjoin($feature, $segment1, $segment2);

This function is synonymous with C<assimilate()>. It is provided only to
aid readability.

=cut

sub adjoin {
	return assimilate(@_);
}

=head2 copy

	copy($feature, $segment1, $segment2);

Copies the value of $feature from $segment1 to $segment2. This does a
"shallow" copy, copying the value but not the underlying reference.

=cut

sub copy {
	my ($feature, $seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);
	$seg2->delink($feature);
	$seg2->$feature( $seg1->$feature );
	return 1;
}

=head2 dissimilate

	dissimilate($feature, $segment1, $segment2);

Dissimilates $segment2 from $segment1 on $feature. If
$segment1->value($feature) is true, then $segment2->value($feature) is set
to false, and vice-versa. The "true" and "false" values tested and returned
may differ depending on whether $feature is privative, binary, or scalar.

If $feature is a node, then if C<< $segment1->value($feature) >> is true, the
node $feature for $segment2 will be delinked. This will cause all children of
$feature to become undefined.  If $segment1->value($feature) is false, no
action is taken, because there is no sensible way to assign a true value to a
node--nodes only return true if they have defined children, and there is no way
to know which child of $feature should be defined. Sorry.

If $segment1 and $segment2 currently have a reference to the same feature,
$segment2 will be assigned a new reference, breaking the connection between
the two segments.

=cut

sub dissimilate {
	my ($feature, $seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);

	# For nodes, assign an empty hash for negative assimilation
	if ($seg1->featureset->type($feature) eq 'node') {
		$seg2->delink($feature) if ($seg1->$feature);
		return 1;
	}

	# For all else, assign values
	# Start by delinking $seg2, whatever it is (avoids the problems w/ shared refs)
	$seg2->delink($feature);

	# decide value and assign it
	$seg1->$feature ? $seg2->$feature(0) : $seg2->$feature(1);
	return 1;
}

=head2 change

	change($segment1, $symbol);

This function changes $segment1 to $symbol, where $symbol is a text string
indicating a symbol in the symbol set associated with $segment1. If
$segment1 doesn't have a symbol set associated with it, this function will
fail.

=cut

sub change {
	my ($seg, $sym) = @_;
	return undef unless is_segment($seg);
	return undef if is_boundary($seg);
	$seg->clear;
	my %new_vals = $seg->symbolset->prototype($sym)->all_values;
	$seg->$_($new_vals{$_}) for (keys %new_vals);
	return 1;
}
	
=head2 metathesize

	metathesize($segment1, $segment2);

This function swaps the order of $segment1 and $segment2. $segment1 MUST be the
first of the two segments, or else this function may result in a
non-terminating loop as the same two segments are swapped repeatedly. (The
exact behavior of this depends on the implementation of
Lingua::Phonology::Rules, which is not a fixed quantity. But things should be
okay if you heed this warning.)

The assumption here is that $segment1 and $segment2 are adjacent segments in
some word currently being processed by Lingua::Phonology::Rules, since the
notion of "segment order" has little meaning outside of this context. Thus,
this function assumes that the INSERT_RIGHT() and INSERT_LEFT() methods are
available (which is only true during a Lingua::Phonology::Rules evaluation),
and will raise errors if this isn't so.

Note that the segments won't actually be switched until after the current
C<do> code reference closes, so you can't make changes to the metathesized
segments immediately after changing them and have the segments be where you
expect them.

=cut

sub metathesize {
	my ($seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);

	# Are we in a rule?
	no warnings 'Lingua::Phonology::Features'; # turn off 'no such feature' warnings
	unless ($seg1->featureset->feature('_RULE')) {
		# Swap references
		$_[0] = $seg2;
		$_[1] = $seg1;
		return 1;
	}

	# If we are in a rule
	if ($seg1->_RULE) {
		# Decide which direction we're going
		if ($seg1->_RULE->{direction} eq 'rightward') {
			$seg1->INSERT_LEFT($seg2->duplicate);
			$seg2->clear;
		} # end if
		elsif ($seg1->_RULE->{direction} eq 'leftward') {
			$seg2->INSERT_RIGHT($seg1->duplicate);
			$seg1->clear;
		} # end elsif
	}
	return 1;
	
}

=head2 metathesize_feature

	metathesize_feature($feature, $segment1, $segment2);

This function swaps the value of $feature for $segment1 with the value of
$feature for $segment2. This is primarily useful if C<$feature = 'ROOT'>,
because in this case all of the true feature values will be swapped, but
the syllabification will not be changed. Then again, that might not be
useful at all.

=cut

sub metathesize_feature {
	my ($feature, $seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);

	my $temp1 = $seg1->$feature;
	my $temp2 = $seg2->$feature;
	$seg1->$feature($temp2);
	$seg2->$feature($temp1);
	return 1;
}

=head2 delete_seg

	delete_seg($segment1);

Deletes $segment1. This is essentially a synonym for calling C<<
$segment1->clear >>, though it's more readable.

=cut

sub delete_seg {
	return undef unless is_segment($_[0]);
	return undef if is_boundary($_[0]);
	$_[0]->clear;
}

=head2 insert

	insert_after($segment1, $segment2);

This function inserts $segment2 after $segment1 in the current word.  Like
L<"metathesize">, this function assumes that it is being called as part of
the C<do> property of a Lingua::Phonology::Rules rule, so any environment
other than this will probably raise errors.

=cut

sub insert_after {
	my ($seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);
	$seg1->INSERT_RIGHT($seg2);
}

=head2 insert_before

	insert_before($segment1, $segment2);

This function inserts $segment2 before $segment1, just like insert_after().
The same warnings that apply to insert_after() apply to this function.

=cut

sub insert_before {
	my ($seg1, $seg2) = @_;
	return undef unless is_segment($seg1, $seg2);
	return undef if is_boundary($seg1, $seg2);
	$seg1->INSERT_LEFT($seg2);
}

sub is_segment {
	for (@_) {
		if (not (UNIVERSAL::isa($_, 'Lingua::Phonology::Segment') or UNIVERSAL::isa($_, 'Lingua::Phonology::PseudoSegment'))) {	
			carp "Argument not a segment" if warnings::enabled();
			return 0;
		} # end if
	} # end for
	return 1;
} #end is_segment

sub is_boundary {
	# turn off those pesky warnings
	no warnings 'Lingua::Phonology::Features';

	# leave if we don't have that feature
	return 0 unless $_[0]->featureset->feature('BOUNDARY');

	# otherwise:
	for (@_) {
		if ($_->BOUNDARY) {
			carp "Attempted modification of boundary" if (warnings::enabled());
			return 1;
		}
	}
	return 0;
} # end is_segment

=head1 SEE ALSO

Lingua::Phonology, Lingua::Phonology::Rules, Lingua::Phonology::Features,
Lingua::Phonology::Segment

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
