#!/usr/bin/perl

package Lingua::Phonology::Syllable;

=head1 NAME

Lingua::Phonology::Syllable;

=head1 SYNOPSIS

	use Lingua::Phonology;
	use Lingua::Phonology::Syllable;

	# Create a new Syllable object
	$syll = new Lingua::Phonology::Syllable;

	# Create an input word
	@word = $phono->symbol->segment('t','a','k','r','o','t');

	# Allow onset clusters and simple codas
	$syll->set_complex_onset;
	$syll->set_coda;

	# Syllabify the word
	$syll->syllabify(@word);

	# @word now has features set to indicate a syllabification of
	# <ta><krot>

=head1 DESCRIPTION

Syllabifies an input word of Lingua::Phonology::Segment objects according
to a set of parameters. The parameters used are well-known linguistic
parameters, so most kinds of syllabification can be handled in just a few
lines of code by setting the appropriate values.

This module uses a special set of features to indicate syllabification.
These features are added to the feature set of the input segments (which
should be a Lingua::Phonology::Features object). The features added are as
follows:

	SYLL	scalar     # Non-zero if the segment has been syllabified
	Rime	privative  # Set if the segment is part of the Rime (i.e. nucleus or coda)
	onset   privative  # Set if the segment is part of the onset
	nucleus privative  # Set if the segment is the nucleus
	coda    privative  # Set if the segment is part of the coda
	SON     scalar     # An integer indicating the calculated sonority of the segment

The module will set these features so that subsequent processing by
Lingua::Phonology::Rules will correctly split the word up into domains or
tiers.

The algorithm and parameters used to syllabify an input word are described
in the L<"Algorithm"> and L<"Parameters"> sections.

=cut

use strict;
use warnings::register;
use Carp;
use Lingua::Phonology::Rules;
use Lingua::Phonology::Functions qw/adjoin/;

our $VERSION = 0.2;

# Properties to use, in name => default format
our %bool = ( 
    complex_onset => 0,
    coda => 0,
	complex_coda => 0
);
our %int = ( 
	min_coda_son => 0,
	min_son_dist => 1,
	max_edge_son => 100,
	min_nucl_son => 3
);
our %list = (
	sonorous => { sonorant => 1,
				  approximant => 1,
				  aperture => 1,
				  vocoid => 1 }
);
our %code = (
	clear_seg => sub {1},
	begin_adjoin => sub {0},
	end_adjoin => sub {0}
);

=head1 METHODS

=head2 new

Returns a new Lingua::Phonology::Syllable object. Takes no arguments.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { RULES => new Lingua::Phonology::Rules,
				 ATTR => {} };
	
	# Initialize $self
	$self->{ATTR}->{$_} = $bool{$_} for keys(%bool);
	$self->{ATTR}->{$_} = $int{$_} for keys(%int);
	$self->{ATTR}->{$_} = $list{$_} for keys(%list);
	$self->{ATTR}->{$_} = $code{$_} for keys(%code);
	
	# Prepare the rules. This is the most important part
	$self->{RULES}->add_rule(
		CalcSon => {
			do => sub { $_[0]->SON($self->sonority($_[0])) }
		},
		Clear => {
			where => sub { &{$self->clear_seg}(@_) },
			do => sub { $_[0]->delink('SYLL', 'onset', 'Rime', 'nucleus', 'coda') }
		},
		CoreSyll => {
			where => sub {
				my $son = $_[0]->SON;
				return 0 if defined $_[0]->SYLL;
				return (($son > $self->max_edge_son) || (($son >= $self->min_nucl_son) && ($son >= $_[-1]->SON && $son >= $_[1]->SON)));
			},
			do => sub {
				$_[0]->nucleus(1) && $_[0]->Rime(1) && $_[0]->SYLL(1);
				if ($_[-1]->SON <= $_[0]->SON && $_[-1]->SON <= $self->max_edge_son && not $_[-1]->SYLL) {
					$_[-1]->onset(1) && adjoin('SYLL', $_[0], $_[-1]);
				}
			}
		},
		ComplexOnset => {
			direction => 'leftward',
			where => sub { (not $_[0]->SYLL)
						   && $_[1]->onset
						   && $_[0]->SON <= $self->max_edge_son
						   && (($_[1]->SON - $_[0]->SON) >= $self->min_son_dist) },
			do => sub { adjoin('onset', $_[1], $_[0]) && adjoin('SYLL', $_[1], $_[0]) }
		},
		Coda => {
			where => sub { (not $_[0]->onset)
						   && $_[-1]->nucleus
						   && $_[0]->SON <= $self->max_edge_son
						   && $_[0]->SON >= $self->min_coda_son },
			do => sub { $_[0]->coda(1) && $_[0]->delink('nucleus'), adjoin('Rime', $_[-1], $_[0]) && adjoin('SYLL', $_[-1], $_[0]) }
		},
		ComplexCoda => {
			direction => 'rightward',
			where => sub { (not $_[0]->SYLL)
						   && $_[-1]->coda
						   && $_[0]->SON <= $self->max_edge_son
						   && $_[0]->SON >= $self->min_coda_son 
						   && (($_[-1]->SON - $_[0]->SON) >= $self->min_son_dist) },
			do => sub { adjoin('coda', $_[-1], $_[0]) && adjoin('Rime', $_[-1], $_[0]) && adjoin('SYLL', $_[-1], $_[0]) }
		},
		BeginAdjoin => {
			direction => 'leftward',
			where => sub {
				my $cond1 = 1 if ((not $_[0]->SYLL) && $_[1]->onset && &{$self->begin_adjoin}(@_));
				my $cond2 = 1;
				my $i = -1;
				while ($cond2 && not $_[$i]->BOUNDARY) {
					$cond2 = 0 if ($_[$i]->SYLL);
					$i--;
				}
				return ($cond1 && $cond2);
			},
			do => sub { adjoin('onset', $_[1], $_[0]) && adjoin('SYLL', $_[1], $_[0]) }
		},
		EndAdjoin => {
			direction => 'rightward',
			where => sub {
				my $cond1 = 1 if ((not $_[0]->SYLL) && $_[-1]->coda && &{$self->end_adjoin}(@_));
				my $cond2 = 1;
				my $i = 1;
				while ($cond2 && not $_[$i]->BOUNDARY) {
					$cond2 = 0 if ($_[$i]->SYLL);
					$i++;
				}
				return ($cond1 && $cond2);
			},
			do => sub { adjoin('coda', $_[-1], $_[0]) && adjoin('Rime', $_[-1], $_[0]) && adjoin('SYLL', $_[-1], $_[0]) }
		}
	);

	# Be blessed
	bless($self, $class);
	return $self;	
} # end new

=head2 syllabify

Syllabifies an input word. The arguments to syllabify() should be a list of
Lingua::Phonology::Segment objects. Those segments will be set to have the
feature values named above (SYLL, Rime, onset, nucleus, coda), according to
the current syllabification parameters.

Note that if you're using this method as part of a Lingua::Phonology::Rules
rule, then the following is almost certainly wrong:

	# Assume that we have a Rules object $rules and Syllable object $syll already
	$rules->add_rule(
		Syllabify => {
			do => sub { $syll->syllabify(@_) }
		}
	);

The preceding rule will needlessly resyllabify the word once for every
segment in the input word. This can be avoided with a simple addition.

	$rules->add_rule(
		Syllabify => {
			direction => 'rightward',
			where => sub { $_[-1]->BOUNDARY },
			do => sub { $syll->syllabify(@_) }
		}
	);

This rule does a simple check to see if it's the first segment in the word,
and then syllabifies. Syllabification only then happens once each time you
apply the rule.

=cut

sub syllabify {
	my $self = shift;

	# Add the necessary features
	$_[0]->featureset->add_feature(
		SYLL => { type => 'scalar' },
		onset => { type => 'privative' },
		Rime => { type => 'privative' },
		nucleus => { type => 'privative' },
		coda => { type => 'privative' },
		SON => { type => 'scalar' }
	);

	# Optimize the rule order
	my @opt = ('Clear', 'CalcSon', 'CoreSyll');
	push(@opt, 'ComplexOnset') if $self->complex_onset;
	push(@opt, 'Coda') if $self->coda;
	push(@opt, 'ComplexCoda') if $self->complex_coda;
	push(@opt, 'BeginAdjoin') if $self->begin_adjoin != $code{begin_adjoin};
	push(@opt, 'EndAdjoin') if $self->end_adjoin != $code{end_adjoin};
	$self->{RULES}->order(@opt);

	# Are we in a rule (is BOUNDARY a feature?)
	if ($_[0]->featureset->feature_exists('BOUNDARY')) {
		# Rewind the word (it fucks us up to start in the middle)
		unshift(@_, pop(@_)) while not $_[-1]->BOUNDARY;
		# Get rid of boundary segments
		pop @_ while $_[-1]->BOUNDARY;
	}

	# Apply
	$self->{RULES}->apply_all(\@_);

} # end syllabify

=head2 sonority

Takes a single Lingua::Phonology::Segment object as its argument, and
returns an integer indicating the current calcuated sonority of the
segment. The integer returned depends on the current value of the
C<sonorous> property. See L<"sonorous"> for more information.

=cut

sub sonority {
	my $self = shift;
	my $seg = shift;
	my $son = 0;
	for (keys(%{$self->sonorous})) {
		$son += $self->{ATTR}->{sonorous}->{$_} if $seg->$_;
	}
	return $son;
} # end sonority

=head1 ALGORITHM

Syllabification algorithms are well-established in linguistic literature;
this module merely implements the general view. Syllabification proceeds in
several steps, the maximum expression of which is given below.
Lingua::Phonology::Syllable may optimize away some of these steps if the
current parameter settings warrant.

=head2 Clearing and calculating sonority

At the beginning of any syllabification, the existing syllabification for a
segment is cleared if that segment meets the conditions in the C<clear_seg>
parameter. The sonority for all segments is also calculated according to
the properties of the C<sonorous> parameter.

=head2 Core syllabification

In this step, basic CV syllables are formed. Nuclei are assigned to
segments that are of equal or greater sonority than both adjacent segments,
and which at least as sonorous as the minimum nucleus sonority
(C<min_nucl_son>). The segments to the left of nuclei are assigned as
onsets if they are not more sonorous than the maximum edge sonority
(C<max_edge_son>) and have not already been assigned as nuclei.

=head2 Complex onset formation

Complex onsets are formed if they are allowed (defined by
C<complex_onset>). As many segments as possible are taken into the onset of
the existing syllables, provided that they do not violate the minimum
sonority distance (C<min_son_dist>) and do not exceed the maximum edge
sonority.

=head2 Coda formation

Codas are formed if they are allowed (defined by C<coda>). A segment to the
left of a nucleus will be assigned to a coda if it has not already been
syllabified as an onset, is less sonorous than the maximum edge sonority, and
is at least as sonorous as the minimum coda sonority (C<min_coda_son>).

=head2 Complex coda formation

Complex codas are formed if they are allowed (defined by C<complex_coda>).
As many segments as possible are taken into the coda, so long as they do
not violate the minimum sonority distance and meet the same conditions
imposed on regular codas.

=head2 Beginning adjunction

Segments at the very beginning of a word may be added to the initial
syllable if special conditions apply. As many segments as possible will be
added to the onset of the initial syllable if there are no syllabified
segments between them and the left edge of the word, and if they meet the
conditions imposed by the C<begin_adjoin> parameter.

=head2 End adjunction

Segments at the very end of a word may be added to the coda of a final
syllable under similar conditions. As many segments as possible will be
added to the final syllable if for each of them there are no syllabified
segments between them and the right edge of the word, and if they meet the
conditions imposed in the C<end_adjoin> parameter.

=head1 PARAMETERS

These parameters are used to determine the behavior of the syllabification
algorithm. They are all accessible with a variety of get/set methods. The
significance of the parameters and the methods used to access them are
described below.

=head2 complex_onset

B<Boolean>, default false.

	# Return the current setting
	$syll->complex_onset;

	# Allow complex onsets
	$syll->complex_onset(1);
	$syll->set_complex_onset;

	# Disallow complex onsets
	$syll->complex_onset(0);
	$syll->no_complex_onset;

If this parameter is true, then complex onsets are allowed. The
syllabification algorithm will greedily take as many segments as possible
into the onset, provided that minimum sonority distance and maximum edge
sonority are respected.

=head2 coda

B<Boolean>, default false.

	# Return the current setting
	$syll->coda;

	# Allow codas
	$syll->coda(1);
	$syll->set_coda;

	# Disallow codas
	$syll->coda(0);
	$syll->no_coda;

If this parameter is true, then a single coda consonant is allowed.

=head2 complex_coda

B<Boolean>, default false.

	# Return the current setting
	$syll->complex_coda; 

	# Allow complex codas
	$syll->complex_coda(1);
	$syll->set_complex_coda;

	# Disallow complex codas
	$syll->complex_coda(0);
	$syll->no_complex_coda;

If this parameter is true, then complex codas are allowed. Setting this
parameter has no effect unless C<coda> is also set. The algorithm will
greedily take as many consonants as possible into the coda, provided that
minimum sonority distance, maximum edge sonority, and minimum coda sonority
are respected.

=head2 min_son_dist

B<Integer>, default 1.

	# Return the current value
	$syll->min_son_dist;

	# Set the value;
	$syll->min_son_dist(2);

This determines the B<min>imum B<son>ority B<dist>ance between members of a
coda or onset. Within a coda or onset, adjacent segments must differ in
sonority by at least this amount. This has no effect unless C<complex_onset> or
C<complex_coda> is set to true. The default value is 1, which means that stop +
nasal sequences like /kn/ will be valid onsets (if complex_onset is true);

=head2 min_coda_son

B<Integer>, default 0.

	# Return the current value
	$syll->min_coda_son;

	# Set the value;
	$syll->min_coda_son(2);

This determines the B<min>imum B<coda> B<son>ority. Coda consonants must be at
least this sonorous in order to be made codas. This is an easy way to, for
example, allow only liquids and glides in codas. The default value is for
anything to be allowed in a coda if codas are allowed at all.

=head2 max_edge_son

B<Integer>, default 100

	# Return the current value
	$syll->max_edge_son;

	# Set the value;
	$syll->max_edge_son(2);

This determines the B<max>imum B<edge> B<son>ority. Segments that are more
sonorous than this value are required to be nuclei, no matter what other
factors might intervene. This is an easy way to, for example, prevent high
vowels from being made into glides. The default value (100) is simply set
to a very high number to imply no particular restriction on what may be an
onset or coda.

=head2 min_nucl_son

B<Integer>, default 3.

	# Return the current value
	$syll->min_nucl_son;

	# Set the value;
	$syll->min_nucl_son(2);

This determines the B<min> B<nucl>eus B<son>ority. Segments that are less
sonorous than this cannot be nuclei, no matter what other factors intervene.
This is useful to rule out syllabic nasals and liquids. The default value (3)
is set so that only vocoids can be nuclei. If you change which features count
towards sonority, this will of course change the significance of the sonority
value 3. Therefore, if you change sonorous(), you should consider if you need
to change this value.

=head2 direction

B<String>, default 'rightward'.

	# Return the current value
	$syll->direction;

	# Set the value
	$syll->direction('leftward');

This determines the direction in which core syllabification proceeds: L->R or
R->L. Since syllable lines are not redrawn after the core syllabification, this
can have important consequences for which segments are nuclei and which are
onsets and codas if there is some ambiguity. This chart gives some examples:

	Outcomes for various scenarios, based on direction
	  Input word          rightward          leftward
	
	No complex onsets or codas
	  /duin/               <du><i>n          d<wi>n
	
	Codas, no complex onsets
	  /duin/               <duj>n            d<win>
	
	Complex onsets and complex codas
	  /duin/               <dujn>            <dwin>

=cut

sub direction {
	my $self = shift;
	my $val = shift;
	if (defined($val)) {
		$self->{RULES}->direction('CoreSyll', $val);
		$self->{RULES}->direction('Coda', $val);
	} # end if
	return $self->{RULES}->direction('CoreSyll');
} # end plateau_nucl

=head2 sonorous

B<Hash reference>, default:

	{
		sonorant => 1,
		approximant => 1,
		vocoid => 1,
		aperture => 1
	}

This is used to calculate the sonority of segments in the word. The value
returned or passed into this method is a hash reference. The keys of this
reference are the names of features, and the values are the amounts by
which sonority is to be increased or decreased if the segment tests true
for those features.

This method returns a hash reference containing all of the current key =>
value pairs. If you pass it a hash reference as an argument, that hash
reference will replace the current one. I often find that for modifying the
existing hash reference, it's easiest to use syntax like C<<
$syll->sonorous->{feature} >> to retrieve a the value for a single key, or
C<< $syll->sonorous->{feature} = $val >> to set a single value.

Note that the sonority() method only tests to see whether the feature values
given as keys are I<true>. There is no way to test for a particular scalar
value. If you want to increase sonority in the case that a particular feature
is false, simply set the value for that feature to be -1. E.g. if you were
using the feature [consonantal] in place of [vocoid], you would want to say C<<
$syll->sonorous->{consonantal} = -1 >>.

The default settings for sonorous(), together with the default feature set
defined in Lingua::Phonology::Features, define the following sonority
classes and values:

	0: Stops and fricatives
	1: Nasals
	2: Liquids
	3: High Vocoids
	4: Non-high vocoids

=cut

sub sonorous {
	my $self = shift;
	my $attrs = shift;
	if (defined $attrs) {
		return err("Non-hash reference argument to sonorous") if ref($attrs) ne 'HASH';
		$self->{ATTR}->{sonorous} = $attrs;
	}
	return $self->{ATTR}->{sonorous};
} # end sonorous

=head2 clear_seg

B<Code>, default C<sub {1}>.

	# Return the current value
	$syll->clear_seg;

	# Set the value
	$syll->clear_seg(\&foo);

This sets the conditions under which a segment should have its
syllabification values cleared and should be re-syllabified from scratch.
The default value is for every segment to be cleared every time. The code
reference passed to C<clear_seg> should follow the same rules as one for
the C<where> property for a rule in Lingua::Phonology::Rules.

=head2 end_adjoin

B<Code>, default C<sub {0}>.

	# Return the current value
	$syll->end_adjoin;

	# Set the value
	$syll->end_adjoin(\&foo);

This sets the conditions under which a segment may be adjoined to the end
of a word. The default is for no end-adjunction at all. The code reference
passed to end_adjoin() should follow the same rules as one for the C<where>
property of a rule in Lingua::Phonology::Rules. Note that additional
constraints other than the ones present in the code reference here must be
met in order for end-adjunction to happen, as described in the
L<"ALGORITHM"> section.

=head2 begin_adjoin

B<Code>, default C<sub {0}>.

	# Return the current value
	$syll->begin_adjoin;

	# Set the value
	$syll->begin_adjoin(\&foo);

This sets the conditions under which a segment may be adjoined to the
beginning of a word. The default is for no beginning-adjunction at all. The
code reference passed to begin_adjoin() should follow the same rules as one
for the C<where> property of a rule in Lingua::Phonology::Rules. Note that
additional constraints other than the ones present in the code reference
here must be met in order for beginning-adjunction to happen, as described
in the L<"ALGORITHM"> section.

=cut

# Automatically load attribute methods
our $AUTOLOAD;
sub AUTOLOAD {
	my $self = shift;
	my $method = $AUTOLOAD;
	$method =~ s/.*:://;
	my $bool_val = 0 if $method =~ s/^no_(\w+)/$1/;
	$bool_val = 1 if $method =~ s/^set_(\w+)/$1/;

	# Integer methods
	if (exists $int{$method}) {
		eval qq! sub $method {
			my \$self = shift;
			my \$val = shift;
			if (defined(\$val)) {
				err("Non-integer argument to $method") if \$val ne int(\$val);
				\$self->{ATTR}->{$method} = int(\$val);
			} # end if
			return \$self->{ATTR}->{$method};
		} # end sub
		!; # end eval
		$self->$method(@_);
	} # end if

	# Boolean methods
	elsif (exists $bool{$method}) {
		if ($bool_val) {
			eval qq! sub set_$method {
				my \$self = shift;
				\$self->{ATTR}->{$method} = 1;
			} #end sub
			!; # end eval
			no strict 'refs';
			&{"set_$method"}($self);
		} # end if
		elsif (defined($bool_val)) {
			eval qq! sub no_$method {
				my \$self = shift;
				\$self->{ATTR}->{$method} = 0;
				return 1;	
			} # end sub
			!; # end eval
			no strict 'refs';
			&{"no_$method"}($self);
		} # end elsif
		else {
			eval qq! sub $method {
				my \$self = shift;
				my \$val = shift;
				if (defined(\$val)) {
					if (\$val) {
						\$self->{ATTR}->{$method} = 1;
					}
					else {
						\$self->{ATTR}->{$method} = 0;
					}
					return 1; # To always return true when assigning
				} # end if
				return \$self->{ATTR}->{$method};
			} # end sub
			!; # end eval
			$self->$method(@_);
		} # end else
	} # end else

	# List methods
	elsif (exists $list{$method}) {
		eval qq! sub $method {
			my \$self = shift;
			my \@list = \@_;
			if (\@list) {
				\$self->{ATTR}->{$method} = \\\@list;
			}
			return \@{\$self->{ATTR}->{$method}};
		} # end sub
		!; # end eval
		$self->$method(@_);
	} # end else

	# Code methods
	elsif (exists $code{$method}) {
		eval qq! sub $method {
			my \$self = shift;
			my \$val = shift;
			if (ref(\$val) eq 'CODE') {
				\$self->{ATTR}->{$method} = \$val;
			}
			elsif (defined(\$val)) {
				err("Non-code reference argument to $method");
			}
			return \$self->{ATTR}->{$method};
		} # end sub
		!; # end eval
		$self->$method(@_);
	} # end else

} # end AUTOLOAD

sub err {
	carp shift if warnings::enabled();
	return undef;
} # end err  

1;

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
