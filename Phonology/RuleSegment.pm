#!/usr/bin/perl

package Lingua::Phonology::RuleSegment;

use Lingua::Phonology::Segment;
our @ISA = ('Lingua::Phonology::Segment');

our $VERSION = 0.1;

# This class subclasses Segment, and adds the INSERT_RIGHT, INSERT_LEFT, etc.
# methods. We subclass all segments gotten by Lingua::Phonology::Rules into
# this class.

# We store values in a package-global hash, with stringified refs as keys. This
# guarantees that all unique refs will not collide, even if they're shallow
# copies of other refs.

our %vals = ();

sub INSERT_LEFT {
	my ($self, $seg) = @_;
	if ($seg) {
		$vals{"$self"}{left} = $seg;
	}
	return $vals{"$self"}{left};
}

sub INSERT_RIGHT {
	my ($self, $seg) = @_;
	if ($seg) {
		$vals{"$self"}{right} = $seg;
	}
	return $vals{"$self"}{right};
}

sub _RULE {
	my ($self, $hash) = @_;
	if ($hash) {
		$vals{"$self"}{rule} = $hash;
	}
	return $vals{"$self"}{rule};
}

# Never ever be a boundary
sub BOUNDARY {
	return undef;
}

# Unclutter %vals
sub DESTROY {
	my $self = shift;
	delete $vals{"$self"};
}

1;
