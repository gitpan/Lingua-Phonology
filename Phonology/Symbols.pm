#!/usr/bin/perl -w

package Lingua::Phonology::Symbols;

=head1 NAME

Lingua::Phonology::Symbols - a module for associating symbols with 
segment prototypes.

=head1 SYNOPSIS

	use Lingua::Phonology;
	$phono = new Lingua::Phonology;

	# Load the default features
	$phono->features->loadfile;

	# Load the default symbols
	$symbols = $phono->symbols;
	$symbols->loadfile;

	# Make a test segment
	$segment = $phono->segment;
	$segment->labial(1);
	$segment->voice(1);

	# Find the symbol matching the segment
	print $symbols->spell($segment);  # Should print 'b'

=head1 DESCRIPTION

This module allows you to associate text strings with Segment objects that
act as prototypes. You can then test other Segment objects against the 
prototypes and get the text string corresponding with the best matching
prototype. In other words, you define a phonetic symbol and the feature
values associated with that symbol, and the Symbols object will then 
evaluate other Segment objects and decide what phonetic symbol best 
represents them.

Within this document, a I<symbol> is a text string, preferably one 
indicating a neat, human-comprehensible phonetic symbol. A
I<prototype> is a Segment object, preferably a minimally defined segment 
that will match only those segments you want it to.

Be sure to read the L<"spell"> section, which describes the algorithm used 
to score potential matches. If you're not getting the results you expect,
you probably need to examine the way your prototype definitions are 
interacting with that algorithm.

=cut

use strict;
use warnings;
use warnings::register;
use Carp;
use Lingua::Phonology::Segment;
use Lingua::Phonology::Default;

=head1 METHODS

=head2 new

Creates a new Symbols object. This method takes one argument, a Features 
object that provides the feature set for the prototypes in this object.
This will carp if you don't provide an appropriate object.

This method is called automatically when you make a C<new
Lingua::Phonology>.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { FEATURES => undef,
				 SYMBOLS => {} };

	my $features = shift;
	return carp "No feature set given" if not $features;
	return carp "Bad feature set given" if not (UNIVERSAL::isa($features, 'Lingua::Phonology::Features'));
	$self->{FEATURES} = $features;

	bless ($self, $class);
	return $self;
} # end init

=head2 symbol

Adds one or more symbols to the current object. The argument to symbol
must be a hashref. The keys of this hashref are the text symbols that 
will be returned, and the values should be Segment objects that act as the
prototypes for each symbol. See L<"spell"> for explanation of
how these symbols and protoypes are used.

If you attempt to pass in a Segment object associated with a feature set
other than the one defined for the current object, symbol() will skip to
the next symbol (and emit a warning, if warnings are turned on).

=cut

sub symbol {
	my $self = shift;
	my $hashref = shift;

	SYMBOL: for my $symbol (keys(%$hashref)) {
		# Carp if you're not given a segment
		unless (UNIVERSAL::isa($hashref->{$symbol}, 'Lingua::Phonology::Segment')) {
			err("Improper symbol prototype for '$symbol'");
			next SYMBOL;
		} # end unless

		# Check that the segment is also associated with the right feature set
		if ($self->features != $hashref->{$symbol}->featureset) {
			err("Prototype for '$symbol' has wrong feature set");
			next SYMBOL;
		} # end if

		# Otherwise, there's not much to do
		$self->{SYMBOLS}->{$symbol} = $hashref->{$symbol};
	} # end SYMBOL
} # end symbol

=head2 drop_symbol

Deletes a symbol from the current object. Nothing happens if you try to 
delete a symbol which doesn't currently exist.

=cut

sub drop_symbol {
	my $self = shift;
	delete ($self->{SYMBOLS}->{ shift });
} # end sub

=head2 change_symbol

Acts exactly the same as symbol(), but first checks to make sure that 
there already exists a symbol with the key given. Otherwise, it brings 
up an error.

The method symbol() can also be used to redefine existing symbols; this 
method is provided only to aid readability.

=cut

sub change_symbol {
	my $self = shift;
	my $hashref = shift;

	SYMBOL: for my $symbol (keys(%$hashref)) {
		if (not $self->symbol_list($symbol)) {
			err("No symbol '$symbol'");
			next SYMBOL;
		} # end if

		# Pass on to symbol
		$self->symbol({$symbol => $hashref->{$symbol}});
	} # end SYMBOL
} # end change_symbol

=head2 loadfile

Takes one argument, a file name, and loads prototype segment definitions
from that file. If no file name is given, loads the default symbol set.

Lines in the file should match the regular expression /^\s*(\S+)\t+(.*)/.
The first parenthesized sub-expression will be taken as the symbol, and the
second sub-expression as the feature definitions for the prototype. Feature
definitions are separated by spaces, and should be in one of two formats:

=over 4

=item *

feature: The preferred way to set a privative value is simply to write the
name of the feature unadorned. Since privatives are either true or undef,
this is sufficient to declare the existence of a privative. E.g., since 
both [labial] and [voice] are privatives in the default feature set, the
following line suffices to define the symbol 'b' (though you may want more
specificity):

	b		labial voice

=item *

[+-]feature: The characters before the feature correspond to setting the 
value to true and false, respectively, if the feature is a binary
feature. This is the preferred way to set binary features. For example, 
the symbol 'd`' for a voiced retroflex stop can be defined with the 
following line:

	d`		-anterior -distributed voice

=item *

feature=value: Whatever precedes the equals sign is the feature name; 
whatever follows is the value. This is the preferred way to set scalar
values, and the only way to set scalar values to anything other than 
undef, 0, or 1.

=back

Feature definitions may work if you use them other than as recommended, 
but the recommended forms are provided for maximum readability. To be 
exact, however, the following are synonymous:

	# Synonymous one way
	labial
	+labial
	labial=1

	# Synonymous in a different way
	-labial # only if 'labial' is binary
	labial=0

Since this behavior is partly dependent on the implementation of text and
number forms in the Features module, the synonymity of these forms is not
guaranteed to remain constant in the future. However, every effort will be
made the guarantee that the I<recommended> forms won't change their
behavior.

Lines whose first character is '#' are assumed to be comments and ignored.

You should only define terminal (non-node) features in your segment 
definitions. The loadfile method is unable to deal with features that
are nodes, and will generate errors if you try to assign to a node.

If you don't give a file name, then the default symbol set is loaded. This
is described in L<"THE DEFAULT SYMBOL SET">.

=cut

sub loadfile {
	my $self = shift;
	my $file = shift;

	if ($file) {
		open $file, $file or return carp "Couldn't open $file: $!";
	}
	else {
		$file = open_default('symbols');
	}
	
	while (<$file>) {
		if (/^\s*([^#]\S*)\t+(.*)/) { # General line format
			my $symbol = $1;
			my @desc = split(/\s+/, $2);

			my $proto = Lingua::Phonology::Segment->new( $self->features );
			for (@desc) {
				if (/(\S+)=(\S+)/) { # Feature defs like coronal=1
					$proto->value($1, $2);
				} # end ifs
				elsif (/([*+-])?(\S+)/) { # Feature defs like +feature or feature
					my $val = $1 ? $1 : 1;
					$proto->value($2, $val);
				}
			} # end for
			$self->{SYMBOLS}->{$symbol} = $proto;
		} # end if
	} # end while

	close $file;
} # end loadfile

=head2 spell

Takes any number of Segment objects. For each object, returns a text
string indicating the best match of prototype with the Segment given.
In a scalar context, returns a string consisting of a cotanencation
of all of the symbols.

The Symbol object given will be compared against every prototype
currently defined, and scored according to the following algorithm:

=over 4

=item *

Score one point for every feature that is defined for both the prototype 
and the comparison segment, and for which the values for those features
agree.

=item *

Lose one point for every feature that is defined for the prototype but is
not defined for the comparison segment.

=item *

Lose two points for every feature that is defined for both the prototype 
and the comparison segment, but for which the values do not agree.

=back

Comparison segments may always be more defined than the prototypes, so 
there is no consequence if the comparison segment is defined for features
that the prototype isn't defined for.

The 'winning' prototype is the one that scores the highest by the 
preceding algorithm. If more than one prototype scores the same, it's 
unpredictable which symbol will be returned, since it will depend on the
order in which they prototypes came out of the internal hash.

If no prototype scores at least 1 point by this algorithm, the string
'_?_' will be returned. This indicates that no suitable matches were 
found.

Beware of testing a Segment object that is associated with a different 
feature set than the ones used by the prototypes. This will almost 
certainly cause errors and bizarre results.

Note that spell() is fairly expensive, and is by far the most costly
routine in the Lingua::Phonology package.

=cut

sub spell {
	my $self = shift;

	my @return = ();
	for my $comp (@_) {
		return err("Bad argument to spell()") if not (UNIVERSAL::isa($comp, 'Lingua::Phonology::Segment'));
		my $winner = scalar($self->score($comp));
		push (@return, $winner ? $winner : '_?_');
	} # end for

	return wantarray ? @return : "@return";
} # end spell
	
=head2 score

Takes a Segment argument and compares it against the defined symbols, just
like symbol(). It normally returns a hash with the available symbols as 
the keys and the score for each symbol as the value. In a scalar context,
returns the winning symbol just like spell(). Useful for debugging
and determining why the program thinks that [a] is better described as 
[d] (as happened to the author during testing). Unfortunately, score() can
only be used to test one segment at a time, rather than a list of 
segments.

=cut

sub score {
	my $self = shift;
	my $comp = shift;
	my %comp = $comp->all_values;

	return err("Bad argument to score()") if not (UNIVERSAL::isa($comp, 'Lingua::Phonology::Segment'));

	# Check the segment against every symbol
	my (%scores, @scores);
	for my $symbol (keys(%{$self->{SYMBOLS}})) {
		my $score = 0;
		my %proto = $self->{SYMBOLS}->{$symbol}->all_values;

		no warnings 'uninitialized'; # Otherwise we get warnings w/ undefs
		for (keys(%proto)) {
			if ($proto{$_} eq $comp{$_}) {
				$score++;
			}
			elsif (not defined($comp{$_})) {
				$score--;
			}
			else {
				$score = $score - 2;
			} # end if/else
		} # end for
		$scores{$symbol} = $score;
		$scores[$score] = $symbol if ($score > 0);
	} # end for

	return wantarray ? %scores : $scores[$#scores];
} # end score

=head2 prototype

Takes one argument, a text string indicating a symbol in the current set.
Returns the prototype associated with that symbol, or carps if no 
such symbol is defined. You can then make changes to the prototype object,
which will be reflected in subsequent calls to spell().

=cut

sub prototype {
	my $self = shift;
	my $symbol = shift;

	my $proto = $self->{SYMBOLS}->{$symbol};
	return carp "No such symbol '$symbol'" if not $proto;
	return $proto;
} # end symbol

=head2 segment

Takes one or more argument, a symbol, and return a new Segment object with the 
feature values of the prototype for that symbol. Unlike L<prototype>, 
which return the prototype itself, this method returns a completely new
object which can be modified without affecting the values of the 
prototype. If you supply a list of symbols, you'll get back a list of
segments in the same order. This is generally the easiest way to make new
segments with some features already set. Example:

	# One segment at a time
	$b = $symbols->segment('b');

	# Many at a time
	@word = $symbols->segment('b', 'a', 'n');

=cut

sub segment {
	my $self = shift;

	# If you're not given a symbol, return a blank segment
	return Lingua::Phonology::Segment->new( $self->features ) unless @_;

	# Otherwise
	my @return;
	while (@_) {
		my $proto = $self->prototype( shift );
		return 0 unless $proto; # So we don't have problems

		my %values = $proto->all_values;
		my $segment = Lingua::Phonology::Segment->new( $self->features );
		# Make a completely new copy by setting all values
		for (keys(%values)) {
			$segment->value($_, $values{$_});
		} # end for

		push (@return, $segment);
	} # end while
	return @return;
} # end new_segment

=head2 features

Take no arguments. Returns the Features object associated with the current
object.

=cut

sub features {
	my $self = shift;
	return $self->{FEATURES};
} # end features

# A very short error writer
sub err {
	carp shift if warnings::enabled();
} # end err

1;

=head1 THE DEFAULT SYMBOL SET

Currently, Lingua::Phonology::Symbols comes with a set of symbols that can
be loaded by calling loadfile with no arguments, like so:

	$symbols->loadfile;

The symbol set thus loaded is based on the X-SAMPA system for encoding the
IPA into ASCII. You can read more about X-SAMPA at
L<http://www.phon.ucl.ac.uk/home/sampa/x-sampa.htm>. The default does not
contain all of the symbols in X-SAMPA, but it does contain a lot of them.
The symbols defined are as follows.

	# Consonants
	# Labial
	p	labial
	b	labial voice
	f	labial +continuant
	v	labial voice +continuant
	m	labial nasal

	# Dental and alveolar
	t	+anterior -distributed
	d	+anterior -distributed voice
	s	+anterior -distributed +continuant
	z	+anterior -distributed voice +continuant 
	T	+anterior +distributed +continuant
	D	+anterior +distributed voice +continuant
	n	+anterior -distributed sonorant nasal
	l	+anterior -distributed sonorant lateral
	r	+anterior -distributed sonorant

	# Palato-alveolar
	tS	-anterior +distributed 
	dZ	-anterior +distributed voice
	S	-anterior +distributed +continuant
	Z	-anterior +distributed +continuant voice

	# Retroflex
	t`	-anterior -distributed
	d`	-anterior -distributed voice
	s`	-anterior -distributed +continuant
	z`	-anterior -distributed +continuant voice
	n`	-anterior -distributed nasal
	r`	-anterior -distributed sonorant *nasal *lateral

	# Velar
	k	dorsal
	g	dorsal voice
	x	dorsal +continuant
	G	dorsal voice +continuant
	N	dorsal nasal

	# Vowels
	# High vowels
	i	vocoid aperture=0 -anterior tense
	I	vocoid aperture=0 -anterior 
	u	vocoid aperture=0 dorsal labial tense
	U	vocoid aperture=0 dorsal labial 
	y	vocoid aperture=0 -anterior labial tense
	Y	vocoid aperture=0 -anterior labial 
	M	vocoid aperture=0 dorsal labial
	1	vocoid aperture=0
	}	vocoid aperture=0 labial

	# Mid vowels
	e	vocoid aperture=1 -anterior tense
	E	vocoid aperture=1 -anterior 
	o	vocoid aperture=1 dorsal labial tense
	O	vocoid aperture=1 dorsal labial
	2	vocoid aperture=1 -anterior labial tense
	9	vocoid aperture=1 -anterior labial
	@	vocoid aperture=1
	8	vocoid aperture=1 labial

	# Low vowels
	a	vocoid aperture=2
	Q	vocoid aperture=2 labial

These symbols depend upon the default feature set. If you aren't using the
default feature set, you're on your own. If you've modified the default
feature set, these may still work, though you'll probably have to tweak
them. YMMV.

=head1 TO DO

Expand the default symbols set.

Add functionality for diacritics to modify imperfect matches.

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
