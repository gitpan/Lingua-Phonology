#!/usr/bin/perl -w

package Lingua::Phonology;

=head1 NAME

Lingua::Phonology - a module providing a unified way to deal with
linguistic representations of phonology.

=head1 SYNOPSIS

	use Lingua::Phonology;

	$phono = new Phonology;

	$features = $phono->features;
	$symbols = $phono->symbols;
	$rules = $phono->rules;
	$segment = $phono->segment;

	# Do with them as you will . . .


=head1 DESCRIPTION

Lingua::Phonology is a unified module for handling phonological
descriptions. It includes sub-modules for linguistic features, phonetic or
orthographic symbols, individual segments, and linguistic rules.

Lingua::Phonology itself is just a meta-module providing easy access to the
sub-modules. The real work is done by the sub-modules, of which there are
currently four:

=over 4

=item *

Lingua::Phonology::Features - handles heirarchical features.

=item *

Lingua::Phonology::Segment - an instantitation of values for a feature set

=item *

Lingua::Phonology::Symbols - a list of symbols used to represent
Lingua::Phonology::Segment objects and methods for spelling them out.

=item * 

Lingua::Phonology::Rules - a set of rules that can be aplied to words of segments.

=back

The description of the function and use of each of these modules is on
their respective man pages. It is recommended that you read these pages in
the order given above to best understand them.

=head1 WARNINGS

Always C<use> them. Lingua::Phonology contains many useful warnings, but it
generally will not display them unless C<use warnings> is on.

Plus, you should do that anyway.

=cut

use v5.6.1;

use strict;
use Carp;

use Lingua::Phonology::Features;
use Lingua::Phonology::Segment;
use Lingua::Phonology::Symbols;
use Lingua::Phonology::Rules;

our $VERSION = 0.01;

=head1 METHODS

=head2 new

Takes no arguments, and returns a new Lingua::Phonology object. This new
object will contain one Lingua::Phonology::Features object, one
Lingua::Phonology::Symbols object, and one Lingua::Phonology::Rules object.
These objects will be initialized to refer to one another where
appropriate, so it is rarely necessary to C<new> on any of the sub-modules.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { FEATURES => undef,
	             SYMBOLS  => undef,
				 RULES    => undef };
	
	$self->{FEATURES} = new Lingua::Phonology::Features;
	$self->{SYMBOLS} = Lingua::Phonology::Symbols->new($self->{FEATURES});
	$self->{RULES} = new Lingua::Phonology::Rules;

	bless $self, $class;
	return $self;
} # end new

=head2 features

Returns the current Features object associated with this phonology. You may
also pass a Features object as an argument, in which case the Features
object for the current phonology is set to that.

=cut

sub features {
	my $self = shift;
	if (@_) {
		my $arg = shift;
		return carp "Bad argument to features()" if not UNIVERSAL::isa($arg, 'Lingua::Phonology::Features');
		$self->{FEATURES} = $arg;
		$self->{SYMBOLS}->{FEATURES} = $arg;
	}
	return $self->{FEATURES};
}

=head2 symbols

Returns the current Symbols object. As with features(), you can pass a
Symbols object as an argument to set the current Symbols object, if
desired.

=cut

sub symbols {
	my $self = shift;
	if (@_) {
		my $arg = shift;
		return carp "Bad argument to symbols()" if not UNIVERSAL::isa($arg, 'Lingua::Phonology::Symbols');
		$self->{SYMBOLS} = $arg;
	}
	return $self->{SYMBOLS};
}

=head2 rules

Returns the current Rules object, or sets the current object if a Rules
object is provided as an argument.

=cut

sub rules {
	my $self = shift;
	if (@_) {
		my $arg = shift;
		return carp "Bad argument to rules()" if not UNIVERSAL::isa($arg, 'Lingua::Phonology::Rules');
		$self->{RULES} = $arg;
	}
	return $self->{RULES};
}

=head2 segment

Returns a new Lingua::Phonology::Segment object. This method takes no
arguments, and cannot be used to initialize a segment. Therefore, it's
probably easier to use the segment() method in Lingua::Phonology::Symbols.

=cut

sub segment {
	my $self = shift;
	return Lingua::Phonology::Segment->new($self->{FEATURES});
}

1;

=head1 APOLOGIA

This module was written to fill my need for a truly versatile, sufficiently
powerful way of handling phonologies. The existing Perl tools
(Lingua::SoundChange and Lingua::FeatureMatrix) worked well enough for what
they did, but they all lacked some functionality that I considered
important. Thus, I decided to make my own tool. I have to a certain extent
reinvented the wheel, but I prefer to think of it as replacing the wheel
with a jet engine, since Lingua::Phonology is much more powerful than the
existing modules.

Nonetheless, I am interested in integrating with existing tools, especially
ones that are widely used and would be useful to others. Feel free to send
me suggestions, or to make your own module interfacing Lingua::Phonology
with whatever else.

=head1 BUGS

Probably. Please send bug reports and code improvements to the author.

=head1 SEE ALSO

Lingua::Phonology::Features, Lingua::Phonology::Symbols,
Lingua::Phonology::Segment, Lingua::Phonology::Rules.

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
