#!/usr/bin/perl

package Lingua::Phonology::Segment::Rules;

use strict;
use warnings;
use Lingua::Phonology::Common;
no overload; # Prevent overloaded stringification

our $VERSION = 0.2;

# This class acts just like a Segment, but adds the INSERT_RIGHT, INSERT_LEFT,
# etc.  methods. It is not a proper subclass, because there's no way to get the
# proper behavior, but the utility function _is_seg is designed to recognize
# this class as a segment also. We are named as if we were an actual subclass.
#
# We store values in a package-global hash, with stringified refs as keys. This
# guarantees that all unique refs will not collide, and we can make an
# arbitrary number of Segment::Rule objects from the same Segment object w/o
# interfering w/ each other.

sub err ($) { warnings::warnif(shift); return; }

sub new {
    my $proto = shift;

    # If new() was called as an object method, the child should take care of it
    return $proto->{seg}->new(@_) if ref $proto;

    # Don't carp here, so that the caller can make their own error message
    my $base = shift;
    return unless _is_seg $base;

    return bless { seg => $base }, $proto;
}

sub _insert {
    my ($self, $dir, $seg) = @_;
    if (defined $seg) {
        return err "Argument to INSERT_$dir not a segment" unless _is_seg $seg;
        $self->{$dir} = $seg;
    }
    return $self->{$dir};
}

sub INSERT_LEFT {
    (shift)->_insert('LEFT', @_);
}

sub INSERT_RIGHT {
    (shift)->_insert('RIGHT', @_);
}

sub _RULE {
	my ($self, $hash) = @_;
	if ($hash) {
		$self->{RULE} = $hash;
	}
	return $self->{RULE};
}

# Don't be a boundary unless the seg you're holding has a method for deciding
sub BOUNDARY {
    my $self = shift;
    return $self->{seg}->BOUNDARY if $self->{seg}->can('BOUNDARY');
	return;
}

# AUTOLOAD dispatches all other methods to the seg
our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://;

    no strict 'refs';
    *$method = sub { (shift)->{seg}->$method(@_); };
    $self->$method(@_);
}

# Don't destroy your children!
sub DESTROY {}

1;
