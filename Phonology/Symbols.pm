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

When using Lingua::Phonology, you usually manipulate Segment objects that have
various feature values that specify the phonetic qualities of the segment.
However, it is difficult to print those feature values, and a list of feature
values can be difficult to interpret anyway. This is where Symbols comes in--it
provides a way to take a Segment object and get a phonetic symbol representing
the properties of that segment.

In Symbols, you may use L<symbol>() to define text symbols that correlate to
"prototypes", which are special Segment objects that represent the ideal
segment for each symbol.  After you have defined your symbols and prototypes,
you may use L<spell>() to find which prototype is the most similar to a segment
in question, and get the symbol for that prototype.

As of v0.2, Symbols also includes diacritics. A diacritic is a special symbol
that begins or ends with a '*', and which is used to modify other symbols. If
the best symbol match for a segment you are trying to spell is an imperfect
match, Symbols will then attempt to use diacritics to indicate exactly how the
segment is pronounced. For compatibility reasons, however, this feature is off
by default. It can be turned on with L<set_diacritics>.

You will probably want to read the L<symbol>, L<spell>, and L<loadfile>
sections, because these describe the most widely-used functions and the
algorithm used to score potential matches. If you're not getting the results
you expect, you probably need to examine the way your prototype definitions are
interacting with that algorithm.

=head1 INDEXING

This section endeavors to explain the purpose of indexing in
Lingua::Phonology::Symbols, and how you can control it.

As of v0.2, this module uses an efficient hash comparison algorithm that
greatly speeds up calls to C<spell> and C<score>. This algorithm works by
compiling an index of the features and values that prototype segments have,
then only comparing against those prototypes that have some chance of winning.
Indexing itself is a somewhat costly procedure, but fortunately, it only needs
to be done once. Unfortunately, it needs to be done again any time that the
list of symbols or the prototypes for those symbols is changed.

Fortunately again, Lingua::Phonology::Symbols will take care of this for you.
Whenever a method is called that might require reindexing, an internal flag on
the object will be set. The next time that you ask this module to C<spell>
something, it will first reindex, then proceed to spelling. The methods that
will trigger reindexing are C<symbol, drop_symbol, change_symbol, loadfile,
prototype>. This reindexing is done "just in time", and isn't done more than is
necessary.

Unfortunately, not all calls to those methods actually warrant reindexing, so
if you call those methods a lot, you might want to have manual control over
when the hash is reindexed. To do this, you can use the method
C<no_auto_reindex>, which will disable automatic reindexing. You then will
have to call C<reindex> yourself whenever it's warranted. If you get tired of
this and want reindexing back, you can call C<set_auto_reindex>.

The author of this module has never felt the need to work with auto reindexing
off, for what it's worth.

=cut

use strict;
use warnings;
use warnings::register;
use Carp;
use Lingua::Phonology::Segment;

our $VERSION = 0.2;

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
	my $self = { FEATURES => undef, # a Features object
				 SYMBOLS => {}, 	# the hash of symbol => prototype
				 DIACRITS => {}, 	# hash of diacritic => prototype
				 USEDCR => 0, 		# whether or not to use diacritics (off by default)
				 INDEX => {}, 		# index of symbols by feature
				 DCRINDEX => [], 	# index of diacritics by number of keys
				 AUTOINDEX => 1, 	# whether or not to autoindex (on by default)
				 REINDEX => 0, 		# whether reindexing is currently necessary
				 VALINDEX => {}, 	# index of features by symbol
				 SAVE => {} }; 		# symbols which are required to be fully scored

	my $features = shift;
	if ((not $features) or (not UNIVERSAL::isa($features, 'Lingua::Phonology::Features'))) {
		carp "No feature set or bad featureset given for new Symbols object";
		return undef;
	}
	$self->{FEATURES} = $features;

	bless ($self, $class);
	return $self;
} # end init

=head2 symbol

Adds one or more symbols to the current object. The argument to symbol must be
a hash. The keys of this hash are the text symbols that will be returned, and
the values should be Segment objects that act as the prototypes for each
symbol. See L<"spell"> for explanation of how these symbols and protoypes are
used.

Symbols can generally be any text string. However, strings beginning or ending
with '*' are interpreted specially, as diacritics. The position of the asterisk
indicates where the base symbol goes, and the rest is interpreted as the
diacritic. Diacritic prototypes are also treated differently from regular
prototypes--see the L<spell> section for details. For example, you could use a tilde '~' following a symbol to indicate nasality with the following call to symbol:

	# Assume $nasal is an appropriate prototye
	$symbols->symbol('*~' => $nasal);

Note that '*' by itself is still a valid, non-diacritic symbol. However, '**'
will be interpreted as a diacritic consisting of a symbol followed by a single
asterisk.

If you attempt to pass in a Segment object associated with a feature set
other than the one defined for the current object, symbol() will skip to
the next symbol and emit a warning, if warnings are turned on.

This method returns true if all of the attempted symbol additions succeeded,
and false otherwise.

=cut

sub symbol {
	my $self = shift;
	my %hash = @_;

	my $return = 1;
	SYMBOL: for my $symbol (keys %hash) {
		# Carp if you're not given a segment
		unless (UNIVERSAL::isa($hash{$symbol}, 'Lingua::Phonology::Segment')) {
			err("Improper symbol prototype for '$symbol'");
			$return = 0;
			next SYMBOL;
		} # end unless

		# Check that the segment is also associated with the right feature set
		if ($self->features ne $hash{$symbol}->featureset) {
			err("Prototype for '$symbol' has wrong feature set");
			$return = 0;
			next SYMBOL;
		} # end if

		# Diacritics
		if ($symbol =~ /(^\*\S+)|(\S+\*$)/) {
			$self->{DIACRITS}->{$symbol} = $hash{$symbol};
		}

		# Regular symbols
		else {
			$self->{SYMBOLS}->{$symbol} = $hash{$symbol};
		}

	} # end SYMBOL
	$self->{REINDEX} = 1;
	return $return;
} # end symbol

=head2 drop_symbol

Deletes a symbol from the current object. Nothing happens if you try to 
delete a symbol which doesn't currently exist.

=cut

sub drop_symbol {
	my $self = shift;
	for (@_) {
		delete ($self->{SYMBOLS}->{$_}) or delete ($self->{DIACRITS}->{$_});
	}
	$self->{REINDEX} = 1;
} # end sub

=head2 change_symbol

Acts exactly the same as symbol(), but first checks to make sure that 
there already exists a symbol with the key given. Otherwise, it brings 
up an error.

The method symbol() can also be used to redefine existing symbols; this 
method is provided only to aid readability.

As with symbol(), this method returns true if all of the attempted changes
succeeded, otherwise false.

=cut

sub change_symbol {
	my $self = shift;
	my %hash = @_;

	my $return = 1;
	SYMBOL: for my $symbol (keys(%hash)) {
		if (not $self->prototype($symbol)) {
			$return = 0;
			next SYMBOL;
		} # end if

		# Pass on to symbol
		$return = $self->symbol($symbol => $hash{$symbol});
	} # end SYMBOL
	$self->{REINDEX} = 1;
	return $return;
} # end change_symbol

=head2 reindex

This function recompiles the internal index that Lingua::Phonology::Symbols
uses to speed up C<spell>ing. It should generally be unnecessary to call this
function, as Lingua::Phonology::Symbols does its best to figure out when
reindexing is necessary without any user input. You may call this function by
hand to ensure reindexing at a particular time, or if auto reindexing is off.

=cut

sub reindex {
	my $self = shift;
	$self->{REINDEX} = 0;
	
	$self->{INDEX} = {};
	for my $symbol (keys %{$self->{SYMBOLS}}) {
		my %feat = $self->{SYMBOLS}->{$symbol}->all_values;
		$self->{VALINDEX}->{$symbol} = \%feat;
		for (keys %feat) {
			# We'll use the SAVE key to indicate those symbols that must not be
			# skipped in round 2 of scoring. These are NOT indexed for those
			# values, because this cannot be reliably scored by the round 1
			# method.
			if (not defined $feat{$_}) {
				$self->{SAVE}->{$symbol} = 1;
			} 
			else {
				push (@{$self->{INDEX}->{$_}->{$feat{$_}}}, $symbol);
			}
		}
	} # end for

	# Also add diacritics to VALINDEX and DCRINDEX (but not the regular index)
	for (keys %{$self->{DIACRITS}}) {
		my %feats = $self->{DIACRITS}->{$_}->all_values;
		$self->{VALINDEX}->{$_} = \%feats;
	}

	# Sort diacritics by number of keys.  If you don't understand why I'm doing
	# this, look at the score_diacrit function.
	my @order = sort 
		{	my %a = $self->{DIACRITS}->{$a}->all_values;
			my %b = $self->{DIACRITS}->{$b}->all_values;
			keys(%b) <=> keys(%a);
		} keys %{$self->{DIACRITS}};
	$self->{DCRINDEX} = \@order;

	return 1;
} # end sub

=head2 auto_reindex

Returns true if automatic reindexing is currently turned on, false otherwise.
If called with an argument, sets auto reindexing to the truth or falsehood of
that argument. Auto reindexing is on by default.

=cut

sub auto_reindex {
	my $self = shift;
	if (exists $_[0]) {
		$self->{AUTOINDEX} = 0;
		$self->{AUTOINDEX} = 1 if $_[0];
	}
	return $self->{AUTOINDEX};
}

=head2 set_auto_reindex

Turns automatic reindexing (back) on. Same as C<auto_reindex(1)>. Auto
reindexing is on by default, so this is only necessary after a call to
C<no_auto_reindex>. See L<INDEXING>.

=cut

sub set_auto_reindex {
	$_[0]->{AUTOINDEX} = 1;
}

=head2 no_auto_reindex

Turns automatic reindexing off. Same as C<< auto_reindex(0) >>. See
L<INDEXING>.

=cut

sub no_auto_reindex {
	$_[0]->{AUTOINDEX} = 0;
	return 1;
}

=head2 diacritics

Returns true if diacritics are currently on, otherwise false. You may also pass
this method an argument to turn diacritics on or off, e.g. C<<
$symbols->diacritics(1) >>. Diacritics are off by default.

=cut

sub diacritics {
	my $self = shift;
	if (exists $_[0]) {
		$self->{USEDCR} = 0;
		$self->{USEDCR} = 1 if $_[0];
	}
	return $self->{USEDCR};
}

=head2 set_diacritics

Turns diacritics on. Same as C<< diacritics(1) >>.

=cut

sub set_diacritics {
	$_[0]->{USEDCR} = 1;
}

=head2 no_diacritics

Turns diacritics off. Same as C<< diacritics(0) >>.

=cut

sub no_diacritics {
	$_[0]->{USEDCR} = 0;
	return 1;
}

=head2 loadfile

Takes one argument, a file name, and loads prototype segment definitions
from that file. If no file name is given, loads the default symbol set.

Lines in the file should match the regular expression /^\s*(\S+)\t+(.*)/.
The first parenthesized sub-expression will be taken as the symbol, and the
second sub-expression as the feature definitions for the prototype. Feature
definitions are separated by spaces, and should be in one of three formats:

=over 4

=item *

B<feature>: The preferred way to set a privative value is simply to write the
name of the feature unadorned. Since privatives are either true or undef, this
is sufficient to declare the existence of a privative. E.g., since both
[labial] and [voice] are privatives in the default feature set, the following
line suffices to define the symbol 'b' (though you may want more specificity):

	b		labial voice

=item *

B<[+-*]feature>: The characters before the feature correspond to setting the
value to true, false, and undef, respectively. This is the preferred way to set
binary features, and the only way to assert that a feature of any type must be
undef. For example, the symbol 'd`' for a voiced retroflex stop can be defined
with the following line:

	d`		-anterior -distributed voice

=item *

B<feature=value>: Whatever precedes the equals sign is the feature name;
whatever follows is the value. This is the preferred way to set scalar values,
and the only way to set scalar values to anything other than undef, 0, or 1.

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

You may begin comments with '#'--anything between the first '#' on a line and
the end of that line will be ignored. Consequently, '#' cannot be used as a
symbol in a loaded file (though it is a valid symbol elsewhere, and can be
assigned via C<symbol()>).

As with C<symbol()>, symbol definitions beginning or ending with '*' will be
interpreted as diacritics. Diacritic symbols may be defined in exactly the same
way as regular symbols. Thus, to define a tilde as a diacritic for nasality,
you might use the following simple line:

	*~		nasal

You should only define terminal (non-node) features in your segment 
definitions. The loadfile method is unable to deal with features that
are nodes, and will generate errors if you try to assign to a node.

If you don't give a file name, then the default symbol set is loaded. This
is described in L<"THE DEFAULT SYMBOL SET">.

=cut

sub loadfile {
	my $self = shift;
	my $file = shift;

	no strict 'refs';
	if ($file) {
		open $file, $file or return err("Couldn't open $file: $!");
	}
	else {
		$file = 'DATA';
	}
	
	while (<$file>) {
		s/#.*$//; # Remove comments
		if (/^\s*(\S*)\t+(.*)/) { # General line format
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
			$self->symbol($symbol => $proto);
		} # end if
	} # end while

	$self->{REINDEX} = 1;
	close $file;
} # end loadfile

=head2 spell

Takes any number of Segment objects as arguments. For each object, returns a
text string indicating the best match of prototype with the Segment given.  In
a scalar context, returns a string consisting of a concatencation of all of the
symbols.

The Symbol object given will be compared against every prototype currently
defined, and scored according to the following algorithm:

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

The 'winning' prototype is the one that scores the highest by the preceding
algorithm. If more than one prototype scores the same, it's unpredictable which
symbol will be returned, since it will depend on the order in which the
prototypes came out of the internal hash.

If C<diacritics> is on, diacritic formation happens after the best-matching
symbol is chosen. A list of the features for which the comparison segment and
symbol prototypes do not agreeis compiled, and diacritics are selected that
match against those features. If there are diacritics that specify more than
one feature, or multiple diacritics specifying the same feature, then this
method will attempt to minimize the number of diacritics used. The diacritic
symbols will be concatenated with the base symbol, the base symbol taking the
place of the asterisk in the symbol definition. For example, if a segment
matched the base symbol 'a' and the diacritic '*~', the resulting symbol would
be 'a~'. If multiple diacritics are matched, there is no way to predict the
order in which they will be added.

If no prototype scores at least 1 point by this algorithm, the string '_?_'
will be returned. This indicates that no suitable matches were found. No
diacritic matching is done in this case.

Beware of testing a Segment object that is associated with a different feature
set than the ones used by the prototypes. This will almost certainly cause
errors and bizarre results.

Note that spell() is fairly expensive (though it's a lot quicker than it used
to be).

=cut

sub spell {
	my $self = shift;

	my @return = ();
	for my $comp (@_) {
		return err("Bad argument to spell()") if not (UNIVERSAL::isa($comp, 'Lingua::Phonology::Segment'));
		my $winner = $self->score($comp);
		push (@return, $winner ? $winner : '_?_');
	} # end for

	return wantarray ? @return : "@return";
} # end spell
	
=head2 score

Takes a Segment argument and compares it against the defined symbols, just like
symbol(). It normally returns a hash with the available symbols as the keys and
the score for each symbol as the value. In a scalar context, returns the
winning symbol just like spell(). Useful for debugging and determining why the
program thinks that [a] is better described as [d] (as happened to the author
during testing). Unfortunately, score() can only be used to test one segment at
a time, rather than a list of segments.

The hash returned from score() may at times contain keys whose values are 0
where they "shouldn't" be. This is because score() uses a lazy algorithm that
stops evaluating once a symbol's score has reached 0 and it cannot go up. Thus,
many symbols will show a score of zero when their score would actually be
negative if evaluation were carried to its conclusion.

=cut

sub score {
	my $self = shift;
	my $comp = shift;

	# Reindex if necessary
	$self->reindex if $self->{REINDEX} and $self->{AUTOINDEX};

	# Prepare data containers
	my %comp = $comp->all_values;
	my %scores = ();
	my @scores = ();

	# Avoid all sorts of harmless warnings
	no warnings 'uninitialized';

	# Round one--check against keys known in %comp
	# This covers cases where comparison and prototypes segs are defined for
	# the feature (but may disagree)
	for my $feature (keys %comp) {
		for (keys %{$self->{INDEX}->{$feature}}) {
			# Increment scores of symbols that agree
			if ($comp{$feature} eq $_) {
				for (@{$self->{INDEX}->{$feature}->{$_}}) {
					$scores{$_}++;
				} # end for
			} # end if

			# Decrement non-agreeing scores by two
			else {
				for (@{$self->{INDEX}->{$feature}->{$_}}) {
					$scores{$_} = $scores{$_} - 2;
				} # end for
			} # end else
		} # end for
	} # end for 

	# Round two--check against the segment prototypes
	# This covers cases where the prototype is defined for the feature but the
	# comparision seg is not--or where the prototype is mandatory undef
	PROTO: for my $proto (keys %{$self->{SYMBOLS}}) {
		# Don't bother unless your score is at least 1 (or you're saved)
		next unless ($scores{$proto} > 0) or $self->{SAVE}->{$proto}; 

		my %proto = %{$self->{VALINDEX}->{$proto}};
		for (keys %proto) {

			# This takes care of the case where $proto is undef but %comp
			# doesn't exist--which should score a point
			if (not defined $proto{$_}) {
				if (not defined $comp{$_}) {
					$scores{$proto}++;
				} 
				else {
					$scores{$proto}--;
				}
			}

			# The normal case
			else {
				$scores{$proto}-- if not defined $comp{$_};
			}

			# If we're at zero, there's no point in continuing (unless were SAVEd)
			next PROTO if ($scores{$proto} == 0) and not $self->{SAVE}->{$proto}; 
		}
		$scores[$scores{$proto}] = $proto if $scores{$proto} > 0;
	} # end for

	# Get a diacritic spelling if wanted
	my $sub = scalar(@scores) ? $#scores : 0;
	if ($self->{USEDCR}) {
		$scores[$sub] = score_diacrit($self, $scores[$sub], %comp);
	}

	return wantarray ? %scores : $scores[$sub];
} # end function

sub score_diacrit {
	my $self = shift;
	my $symbol = shift;
	my %comp = @_;

	# Don't try to diacriticize completely unmatched segments
	return '' if not $symbol;

	# Avoid warnings
	no warnings 'uninitialized';

	# Build hash of discrepancy
	my %disc = ();
	for (keys %comp) {
		$disc{$_} = $comp{$_} if $comp{$_} ne $self->{VALINDEX}->{$symbol}->{$_};
	}
	for (keys %{$self->{VALINDEX}->{$symbol}}) {
		$disc{$_} = $comp{$_} if $comp{$_} ne $self->{VALINDEX}->{$symbol}->{$_};
	}
		

	# Use an algorithm similar to the Round Two algorithm above
	DIACRIT: for (@{$self->{DCRINDEX}}) {
		# Quit if there's no more discrepancy
		last if not keys %disc;

		my $dcr = $_;
		my %proto = %{$self->{VALINDEX}->{$dcr}};
		for (keys %proto) {
			if (defined $proto{$_}) {
				next DIACRIT if ($proto{$_} ne $disc{$_});
			}
			else {
				next DIACRIT unless (exists $disc{$_}) and (not defined $disc{$_});
			}
		}

		# If you get here, you agree on all features, so you should be added
		# Don't allow anybody else to match your features
		delete $disc{$_} for keys %proto;
		# Add yourself to the beginning or ending, chopping the leading/trailing '*'
		if ($dcr =~ s/^\*//) {
			$symbol .= $dcr;
		}
		else {
			$dcr =~ s/\*$//;
			$symbol = $dcr . $symbol;
		}
	} # end for

	return $symbol;
}

=head2 prototype

Takes one argument, a text string indicating a symbol in the current set.
Returns the prototype associated with that symbol, or carps if no 
such symbol is defined. You can then make changes to the prototype object,
which will be reflected in subsequent calls to spell().

=cut

sub prototype {
	my $self = shift;
	my $symbol = shift;
	my $proto;

	if ($symbol =~ /(^\*)|(\*$)/) {
		$proto = $self->{DIACRITS}->{$symbol};
	}
	else {
		$proto = $self->{SYMBOLS}->{$symbol};
	}

	return err("No such symbol '$symbol'") if (not $proto);
	$self->{REINDEX} = 1;
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

The segments returned from this method will already be associated with the
current Lingua::Phonology::Features object and the current Symbols object.

=cut

sub segment {
	my $self = shift;

	# If you're not given a symbol, return a blank segment
	unless (@_) {
		my $ret = Lingua::Phonology::Segment->new( $self->features );
		$ret->symbolset($self);
		return $ret;
	}

	# Otherwise
	my @return;
	while (@_) {
		my $proto = $self->prototype( shift );
		return undef unless $proto; # So we don't have problems

		my %values = $proto->all_values;
		my $segment = Lingua::Phonology::Segment->new($self->features, \%values);
		$segment->symbolset($self);
		push (@return, $segment);
	} # end while
	return wantarray ? @return : $return[0];
} # end new_segment

=head2 features

Returns the Features object associated with the current object, or sets the
object if provided with a Lingua::Phonology::Features object as an
argument.

=cut

sub features {
	my $self = shift;
	if (@_) {
		my $arg = shift;
		return carp "Bad argument to features()" if not UNIVERSAL::isa($arg, 'Lingua::Phonology::Features');
		$self->{FEATURES} = $arg;
	}
	return $self->{FEATURES};
} # end features

# A very short error writer
sub err {
	carp shift if warnings::enabled();
	return undef;
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

	# Symbol definitions
	# Labial
	p	labial -continuant
	b	labial voice -continuant
	f	labial +continuant
	v	labial voice +continuant
	m	labial sonorant nasal -continuant

	# Dental and alveolar
	t	+anterior -continuant
	d	+anterior voice -continuant
	s	+anterior -distributed +continuant
	z	+anterior -distributed voice +continuant 
	T	+anterior +distributed +continuant
	D	+anterior +distributed voice +continuant
	n	+anterior sonorant nasal -continuant
	l	+anterior sonorant lateral approximant
	r	+anterior sonorant approximant

	# Palato-alveolar
	tS	-anterior +distributed -continuant
	dZ	-anterior +distributed voice -continuant
	S	-anterior +distributed +continuant
	Z	-anterior +distributed +continuant voice

	# Retroflex
	t`	-anterior -distributed -continuant
	d`	-anterior -distributed voice -continuant
	s`	-anterior -distributed +continuant
	z`	-anterior -distributed +continuant voice
	n`	-anterior -distributed sonorant nasal -continuant
	l`	-anterior -distributed sonorant lateral approximant
	r`	-anterior -distributed sonorant approximant

	# Palatal
	c	-anterior dorsal -continuant
	d\	-anterior dorsal -continuant voice
	C	-anterior dorsal +continuant
	j\	-anterior dorsal +continuant voice
	J	-anterior dorsal -continuant sonorant nasal
	L	-anterior dorsal sonorant lateral approximant

	# Velar
	k	dorsal -continuant
	g	dorsal voice -continuant
	x	dorsal +continuant
	G	dorsal voice +continuant
	N	dorsal sonorant nasal -continuant

	# Uvular
	q	dorsal pharyngeal -continuant
	G\	dorsal pharyngeal -continuant voice
	X	dorsal pharyngeal +continuant
	R	dorsal pharyngeal +continuant voice
	N\	dorsal pharyngeal sonorant nasal -continuant
	R\	dorsal pharyngeal sonorant approximant

	# Pharyngeal
	q\	pharyngeal -continuant
	X\	pharyngeal +continuant
	?\	pharyngeal +continuant voice

	# Glottal
	?	-continuant
	h	+continuant
	h\	+continuant voice

	# Vowels and vocoids
	# High vowels
	i	vocoid approximant sonorant aperture=0 -anterior tense
	j	vocoid approximant sonorant aperture=0 -anterior tense *nucleus
	I	vocoid approximant sonorant aperture=0 -anterior 
	u	vocoid approximant sonorant aperture=0 dorsal labial tense
	w	vocoid approximant sonorant aperture=0 dorsal labial tense *nucleus
	U	vocoid approximant sonorant aperture=0 dorsal labial 
	y	vocoid approximant sonorant aperture=0 -anterior labial tense
	Y	vocoid approximant sonorant aperture=0 -anterior labial 
	M	vocoid approximant sonorant aperture=0 dorsal labial
	1	vocoid approximant sonorant aperture=0
	}	vocoid approximant sonorant aperture=0 labial

	# Mid vowels
	e	vocoid approximant sonorant aperture=1 -anterior tense
	E	vocoid approximant sonorant aperture=1 -anterior 
	o	vocoid approximant sonorant aperture=1 dorsal labial tense
	O	vocoid approximant sonorant aperture=1 dorsal labial
	V	vocoid approximant sonorant aperture=1 dorsal
	2	vocoid approximant sonorant aperture=1 -anterior labial tense
	9	vocoid approximant sonorant aperture=1 -anterior labial
	@	vocoid approximant sonorant aperture=1
	8	vocoid approximant sonorant aperture=1 labial

	# Low vowels
	a	vocoid approximant sonorant aperture=2
	Q	vocoid approximant sonorant aperture=2 labial

	# Diacritics
	*_0		*voice
	*_v		voice
	*_h		spread
	*_~		constricted
	*_w		labial
	*_G		dorsal
	*_?\	pharyngeal
	*_d		+distributed # Diacritic for "dental"
	*~		nasal
	*_l		lateral

These symbols depend upon the default feature set. If you aren't using the
default feature set, you're on your own. If you've modified the default
feature set, these may still work, though you'll probably have to tweak
them. YMMV.

=head1 TO DO

Expand the default symbols set.

Add functionality for diacritics to modify imperfect matches.

=head1 SEE ALSO

Lingua::Phonology, Lingua::Phonology::Features

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut

__DATA__

# Symbol definitions
# Labial
p	labial -continuant
b	labial voice -continuant
f	labial +continuant
v	labial voice +continuant
m	labial sonorant nasal -continuant

# Dental and alveolar
t	+anterior -continuant
d	+anterior voice -continuant
s	+anterior -distributed +continuant
z	+anterior -distributed voice +continuant 
T	+anterior +distributed +continuant
D	+anterior +distributed voice +continuant
n	+anterior sonorant nasal -continuant
l	+anterior sonorant lateral approximant
r	+anterior sonorant approximant

# Palato-alveolar
tS	-anterior +distributed -continuant
dZ	-anterior +distributed voice -continuant
S	-anterior +distributed +continuant
Z	-anterior +distributed +continuant voice

# Retroflex
t`	-anterior -distributed -continuant
d`	-anterior -distributed voice -continuant
s`	-anterior -distributed +continuant
z`	-anterior -distributed +continuant voice
n`	-anterior -distributed sonorant nasal -continuant
l`	-anterior -distributed sonorant lateral approximant
r`	-anterior -distributed sonorant approximant

# Palatal
c	-anterior dorsal -continuant
d\	-anterior dorsal -continuant voice
C	-anterior dorsal +continuant
j\	-anterior dorsal +continuant voice
J	-anterior dorsal -continuant sonorant nasal
L	-anterior dorsal sonorant lateral approximant

# Velar
k	dorsal -continuant
g	dorsal voice -continuant
x	dorsal +continuant
G	dorsal voice +continuant
N	dorsal sonorant nasal -continuant

# Uvular
q	dorsal pharyngeal -continuant
G\	dorsal pharyngeal -continuant voice
X	dorsal pharyngeal +continuant
R	dorsal pharyngeal +continuant voice
N\	dorsal pharyngeal sonorant nasal -continuant
R\	dorsal pharyngeal sonorant approximant

# Pharyngeal
q\	pharyngeal -continuant
X\	pharyngeal +continuant
?\	pharyngeal +continuant voice

# Glottal
?	-continuant
h	+continuant
h\	+continuant voice

# Vowels and vocoids
# High vowels
i	vocoid approximant sonorant aperture=0 -anterior tense
j	vocoid approximant sonorant aperture=0 -anterior tense *nucleus
I	vocoid approximant sonorant aperture=0 -anterior 
u	vocoid approximant sonorant aperture=0 dorsal labial tense
w	vocoid approximant sonorant aperture=0 dorsal labial tense *nucleus
U	vocoid approximant sonorant aperture=0 dorsal labial 
y	vocoid approximant sonorant aperture=0 -anterior labial tense
Y	vocoid approximant sonorant aperture=0 -anterior labial 
M	vocoid approximant sonorant aperture=0 dorsal labial
1	vocoid approximant sonorant aperture=0
}	vocoid approximant sonorant aperture=0 labial

# Mid vowels
e	vocoid approximant sonorant aperture=1 -anterior tense
E	vocoid approximant sonorant aperture=1 -anterior 
o	vocoid approximant sonorant aperture=1 dorsal labial tense
O	vocoid approximant sonorant aperture=1 dorsal labial
V	vocoid approximant sonorant aperture=1 dorsal
2	vocoid approximant sonorant aperture=1 -anterior labial tense
9	vocoid approximant sonorant aperture=1 -anterior labial
@	vocoid approximant sonorant aperture=1
8	vocoid approximant sonorant aperture=1 labial

# Low vowels
a	vocoid approximant sonorant aperture=2
Q	vocoid approximant sonorant aperture=2 labial

# Diacritics
*_0		*voice
*_v		voice
*_h		spread
*_~		constricted
*_w		labial
*_G		dorsal
*_?\	pharyngeal
*_d		+distributed # Diacritic for "dental"
*~		nasal
*_l		lateral

__END__
