#!/usr/bin/perl

package Lingua::Phonology::Rules;

=head1 NAME

Lingua::Phonology::Rules - a module for defining and applying
phonological rules.

=head1 SYNOPSIS

	use Lingua::Phonology;
	$phono = new Lingua::Phonology;

	$rules = $phono->rules;

	# Adding and manipulating rules is discussed in the "WRITING RULES"
	# section

=head1 DESCRIPTION

This module allows for the creation of linguistic rules, and the
application of those rules to "words" of Segment objects. To achieve 
maximum flexibility, this module simply provides a framework for defining 
the conditions and cyclicity of rules. The actual operations of the rule 
is defined by the user and passed in to Rules as a code reference. This
allows the user to define any sort of rule that he wants and makes it easy
to use outside subroutines in the creation of rules.

Lingua::Phonology::Rules is flexible and powerful enough to handle any 
sequential type of rule system. It cannot handle Optimality Theory-style
processes, because those require a fundamentally different kind of 
algorithm.

=cut

use strict;
use warnings::register;
use Carp;
use Lingua::Phonology::Segment;
use Lingua::Phonology::PseudoSegment;

our $VERSION = 0.11;

=head1 METHODS

=head2 new

Returns a new Lingua::Phonology::Rules object. This method accepts no 
arguments.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { RULES => { },
				 ORDER => [ ],
				 PERSIST => [ ] };
	bless ($self, $class);
	return $self;
} # end new

=head2 add_rule

Adds one or more rules to the list. Takes a series of key-value pairs, where
the keys are the names of rules to be added, and the values are hashrefs. The
following are accepted as keys for the value hashref:

=over 4

=item *

B<tier> - defines the tier on which the rule applies. Must be the name of
a feature in the feature set for the segments of the word you pass in.

=item *

B<domain> - defines the domain within which the rule applies. Must also be
the name of a feature.

=item *

B<direction> - defines the direction that the rule applies in. Must be 
either 'leftward' or 'rightward.' If no direction is given, defaults to
'rightward'.

=item *

B<filter> - defines a filter for the segments that the rule applies on.
Must a code reference that returns a truth value.

=item *

B<where> - defines the condition or conditions where the rule applies. Must be a 
coderef that returns a truth value. If no value is given, defaults to 
always true.

=item *

B<do> - defines the action to take when the C<where> condition is met. Must be
a code reference. If no value is given, does nothing.

=back

A detailed explanation of how to use these to make useful rules is in 
L<WRITING RULES>. A typical call to add_rule might look like what 
follows. Assume that 'nasal' and 'SYLLABLE' are defined in the feature set
you're using, and that nasalized() and denasalize() are subroutines 
defined elsewhere.

	$rules->add_rule( Denasalization => { tier => 'nasal',        # A feature name
	                                       domain => 'SYLLABLE',  # Another feature name
										   direction => 'rightward',
										   where => \&nasalized,  # A code reference
										   do => \&denasalize     # Another code reference
	});

This method returns true if all rules were added successfully, otherwise false;

=cut

# Defines valid properties for rules
our %property = ( where => 1,
			  do	=> 1,
			  tier  => 1,
			  filter => 1,
			  domain => 1,
			  direction => 1 );

sub add_rule {
	my $self = shift;
	my %rules = @_;

	my $return = 1;
	RULE: for my $rule (keys(%rules)) {
		my $params = $rules{$rule};

		# Check all of the possible parameters for type
		# Tier and domain are not checkable, since they depend on the
		# current featureset. If you give bad ones, errors will arise on 
		# execution. (Is there a way around this?)

		# Check directionality
		$params->{direction} = lc $params->{direction};
		$params->{direction} = 'rightward' if not $params->{direction}; # Default
		if ($params->{direction} ne 'rightward' && $params->{direction} ne 'leftward') {
			err("Improper direction for rule $rule");
			$return = 0;
			next RULE;
		} # end if
		
		# Set defaults for where and do
		$params->{where} = sub {1} if not $params->{where}; # Default to always true
		$params->{do} = sub {} if not $params->{do}; # Default to nothing
		for ('filter','where','do') {
			if ($params->{$_}) {
				if (ref($params->{$_}) ne 'CODE') {
					err("$_ for $rule is not a code reference");
					$return = 0;
					next RULE;
				}
			}
		}

		# If you get this far, you're okay
		$self->{RULES}->{$rule} = $params;
	} # end for
	return $return;
} # end sub

=head2 clear

Resets the Lingua::Phonology::Rules object by deleting all rules and all
rule ordering.

=cut

sub clear {
	my $self = shift;
	$self->{RULES} = {};
	$self->{ORDER} = [];
	$self->{PERSIST} = [];
	return 1;
} # end sub

=head2 tier

See below.

=head2 domain

See below.

=head2 direction

See below.

=head2 filter

See below.

=head2 where

See below.

=head2 do

All of these methods behave identically. They may take one or two 
arguments. The first argument is the name of a rule. If only one argument
is given, then these return the property of the rule that they name. If 
two arguments are given, then they set that property to the second 
argument. For example:

	$rules->tier('Rule');				# Returns the tier
	$rules->tier('Rule', 'feature');	# Sets the tier to 'feature'
	$rules->domain('Rule');				# Returns the domain
	$rules->domain('Rule', 'feature');	# Sets the domain to 'feature'
	# Etc., etc.

DIRE WARNINGS: These methods do not do any checking for appropriateness of
input. Therefore, if you use one of these methods to set a rule property to an
improper value, you won't find out until you attempt to execute the rule, at
which point you'll get (potentially fatal) errors.

=cut

# Private functions needed by apply()

# Features we use
our %features = ( BOUNDARY => { type => 'privative' },
				  INSERT_RIGHT => { type => 'scalar' },
				  INSERT_LEFT => { type => 'scalar' },
				  _NEW => { type => 'privative' },
				  _RULE => { type => 'scalar' }
);

# A simplistic func to flatten hashrefs into easily comparable strings
sub flatten {
	my $thing = shift;
	return $thing if ref($thing) ne 'HASH';
	my $return = '';
	for (keys(%$thing)) {
		$return .= flatten($thing->{$_});
	} # end for
	return $return;
} # end if
	
# Make a domain
our $make_domain = sub {
	my $domain = shift;
	my @word = @_;
	my @return = ();

	my $i = 0;
	while ($i < scalar(@word)) {
		my @domain = ();
		push(@domain, $word[$i]);

		# Keep adding segments as long as they are references to the same thing
		while ($word[$i+1] && flatten($word[$i]->value_ref($domain)) eq flatten($word[$i+1]->value_ref($domain))) {
			$i++;
			push (@domain, $word[$i]);
		} #end while

		push (@return, \@domain);
		$i++;
	} # end while

	return @return;
}; # end $make_domain

# Make tiers
our $make_tier = sub {
	my $tier = shift;
	my (@return, @temp);
	for (@_) {
		push (@temp, $_) if (defined($_->value($tier)));
	} # end for

	# Define pseudo-segments
	@temp = &$make_domain($tier, @temp);
	for (@temp) {
		push (@return, Lingua::Phonology::PseudoSegment->new(@$_));
	} # end for

	return @return;
}; # end make_tier

# Readably do the rotations
our $rightward = sub {
	push(@_, shift(@_));
	return @_;
}; # end rotate

our $leftward = sub {
	unshift(@_, pop(@_));
	return @_;
}; # end rotate

# Return only list elements that have some values set and include
# INSERT_LEFT and INSERT_RIGHT segments
our $cleanup = sub {
	my @return = ();
	for (@_) {
		next if not $_;
		my ($right, $left);
		if ($left = $_->INSERT_LEFT) {
			# $left->_NEW(1);
			push(@return, $left);
			# $_->delink('INSERT_LEFT');
		} # end if
		push (@return, $_);
		if ($right = $_->INSERT_RIGHT) {
			# $right->_NEW(1);
			push(@return, $right);
			# $_->delink('INSERT_RIGHT');
		} # end if
	} # end for
	# This line is ugly, but the nicer keys($_->all_values) didn't work. WTF?
	return grep { my %hash = $_->all_values; scalar(keys(%hash)) } @return;
}; # end cleanup

# Make the fully modified string reconstructible so that $cleanup will put
# it back how it should be
our $reconstruct = sub {
	for (0 .. $#_) {
		if ($_[$_]->_NEW) {
			if ($_[$_ - 1]->BOUNDARY) {
				$_[$_ + 1]->INSERT_LEFT($_[$_]);
			} # end if
			else {
				$_[$_ - 1]->INSERT_RIGHT($_[$_]);
			} # end else
		} # end if
	} # end for
	return @_;
}; # end reconstruct


# Actually execute the code
our $execute = sub {

	my $self = shift;
	my $rule = shift;
	return if not @_; # What's left of @_ is the segment list

	# Create boundary segments
	my $bound = Lingua::Phonology::Segment->new( $_[0]->featureset ); 
	$bound->BOUNDARY(1);
	push (@_, $bound);
	unshift (@_, $bound);

	# Get the important properties
	my $filter = $self->filter($rule);
	my $where = $self->where($rule);
	my $do = $self->do($rule);
	my $dir = $self->direction($rule);

	# Make properties available via _RULE
	$_->_RULE($self->{RULES}->{$rule}) for (@_);

	# Apply the filter; always allow BOUNDARY segments through
	@_ = grep { &$filter($_) || $_->BOUNDARY } @_ if $filter;

	# Rotate to starting positions
	my $next;
	if ($dir eq 'leftward') {
		@_ = &$leftward(@_); # We need one extra rotation for leftward
		$next = $leftward;
	} # end if
	else {
		$next = $rightward;
	} # end if
	@_ = &$next(@_);

	# Count the times the rule applies
	my $count = 0;

	# Iterate over each segment
	do {
		# @_ = &$cleanup(@_); # This cleanup only affects the local @_
		if (&$where(@_)) {
			&$do(@_);
			$count++;
		} # end if
		# Rotate to the next segment
		@_ = &$next(@_);
		
		# If someone has destroyed our features, put them back before bad
		# things happen
		if (not $_[0]->featureset->feature('BOUNDARY')) {
			$_[0]->featureset->add_feature(%features);
		}
	} # end do
	while (not $_[0]->BOUNDARY);

	# Do final cleanup and reconstruction
	# &$reconstruct(&$cleanup(@_));
	return $count;
}; # end execute

=head2 apply

Applies a rule to a "word". The first argument to this function is the 
name of a rule, and the second argument is a reference to an array of 
Segment objects. Apply() will take the rule named and apply it to each segment
in the array, after doing some appropriate magic with the tiers and the 
domains, if specified. For a full explanation on how apply() works and how
to exploit it, see below in L<WRITING RULES>. Example:

	$rules->apply('Denasalization', \@word); # Word must be an array of Segment objects

As of v.0.1, the return value of apply() is an integer indicating how many
times the rule applied (i.e. how many times the C<do> property was actually
executed).

=head2 Applying rules by name

You may also call rule names themselves as methods, in which case the only
needed arguments are the segments of the word. Thus, the following is
exactly identical to the preceding example:

	$rules->Denazalization(\@word);

WARNING: If you attempt to call a rule in this form and the rule has the 
same name as a reserved word in perl, the program will get trapped in a 
non-terminating loop. So don't do that. Use the longer form with apply()
instead.

=cut

sub apply {
	my ($self, $rule, $word) = @_;

	return err("No such rule $rule") if not exists($self->{RULES}->{$rule});
	return 0 if not @$word;
	
	# Check that we have good segments
	for (@$word) {
		if (not UNIVERSAL::isa($_, 'Lingua::Phonology::Segment')) {
			carp "Bad arguments to apply";
			return 0;
		}
	}
	
	# Assume that all segments share a featureset, and add our pseudo-features to that set
	my $featureset = $word->[0]->featureset; 
	$featureset->add_feature(%features);
	
	# Count the times the rule applies (to be incremented in &$execute)
	my $count = 0;

	my $tier = $self->tier($rule);
	# Set up domains and execute on them, if needed
	if (my $domain = $self->domain($rule)) {
		my @domains = &$make_domain($domain, @$word);
		for (@domains) {
			if ($tier) {
				$count += &$execute($self, $rule, &$make_tier($tier, @$_));
			}
			else {
				$count += &$execute($self, $rule, @$_);
			} # end if/else
		} # end for
	} #end if

	# If there are no domains specified, simply execute on the whole word
	else {
		if ($tier) {
			$count += &$execute($self, $rule, &$make_tier($tier, @$word));
		}
		else { 
			$count += &$execute($self, $rule, @$word);
		} # end if/else
	} # end else

	# Clean up the word
	# These actually affect the output word directly
	@$word = &$cleanup(@$word);

	# Remove our temporary feature settings
	for my $feature (keys(%features)) {
		$_->delink($feature) for (@$word);
		$featureset->drop_feature($feature);
	} # end for

	return $count;
} #end if

# Makes rules appliable by their name
our $AUTOLOAD;
sub AUTOLOAD {
	my $method = $AUTOLOAD;
	$method =~ s/.*:://;
	no strict 'refs';

	# For calling rules by name
	if ($_[0]->{RULES}->{$method}) {
		# Compile functions which are rules
		eval qq! sub $method {
			my (\$self, \$word) = \@_;
			\$self->apply($method, \$word);
			} # end sub
		!;

		# Go to the rule
		goto &$method;
	} # end if

	# Otherwise, try to find rule properties
	elsif ($property{$method}) {
		# Compile into rule property functions
		eval qq! sub $method {
			my \$self = shift;
			my \$rule = shift;
			return err("no such rule '\$rule'") if not exists \$self->{RULES}->{\$rule};
			my \$ruleref = \$self->{RULES}->{\$rule};
			\$ruleref->{$method} = shift if \@_;
			return \$ruleref->{$method};
			} # end sub
		!;

		# Go to the rule
		goto &$method;
	} # end elsif
	
} # end AUTOLOAD

sub DESTROY {} # To avoid catching DESTROY in AUTOLOAD

=head2 apply_all

When used with persist() and order(), this method can be used to apply all
rules to a word with one call. The argument to this method should be a 
list of Segment objects, just as with apply(). 

Calling apply_all() applies the rules in the order specified by order(), 
applying the rules in persist() before and after every one. Rules that are
part of the current object but which aren't specified in order() or
persist() are not applied. See L<"order"> and L<"persist"> for details on 
those methods.

As of v0.1, apply_all() in list context returns a hash whose keys are the
names of rules, and whose values are the number of times each rule applied.
In scalar context, it returns the sum of all the times that a rule was
applied.

=cut

sub apply_all {
	my ($self, $word) = @_;
	my %return = ();
	
	my @persist = $self->persist; # Only get this once, for speed
	for ($self->order) {
		for (@persist) {
			$return{$_} = $self->apply($_, $word);
		} # end for
		$return{$_} = $self->apply($_, $word);
	} # end for

	# Apply persistent rules one last time before finishing
	for (@persist) {
		$return{$_} = $self->apply($_, $word);
	} # end for

	if (wantarray) {
		return %return;
	}
	elsif (defined wantarray) {
		my $count;
		$count += $_ for values %return;
		return $count;
	}
} # end sub

=head2 order

If called with no arguments, returns an array of the current order in 
which rules apply when calling apply_all(). If called with one or more
arguments, this sets the order in which rules apply. The arguments should
be the string names of rules in the current object.

=cut

sub order {
	my $self = shift;
	$self->{ORDER} = \@_ if @_;
	return @{$self->{ORDER}};
} # end sub

=head2 persist

If called with no arguments, returns an array of the current order in 
which persistent rules apply when calling apply_all(). Persistent rules
are applied at the beginning and end of rule processing and between every
rule in the middle. Calling this with one or more arguments assigns the 
list of persistent rules (and knocks out the existing list). Example:

	# Assume that the rule names given here have already been defined
	$rules->persist('Redundancy', 'Syllabify');
	$rules->order('VowelHarmony', 'VowelDeletion', 'Assimilation');
	$rules->apply_all(\@word);

=cut

sub persist {
	my $self = shift;
	$self->{PERSIST} = \@_ if @_;
	return @{$self->{PERSIST}};
} # end sub

1;

# A very short error writer
sub err {
	carp shift if warnings::enabled();
	return undef;
} # end err

=head1 WRITING RULES

=head2 Overview of the rule algorithm

The details of the algorithm, of course, are the module's business. But
here's a general overview of what goes on in the execution of a rule:

=over 4

=item *

The segments of the input word are broken up into domains, if a domain is
specified. This is discussed in L<"using domains">.

=item *

The segments of each domain are taken and the tier, if there is one, is
applied to it.  This always reduces the number of segments being evaluated.
Details of this process are discussed below in L<"using tiers">.

=item *

The segments remaining after the tier is applied are passed through the
filter. Segments for which the filter evaluates to true are passed on to
the executer.

=item *

Executing the rule involves examining every segment in turn and deciding if
the criteria for applying the rule, defined by the C<where> property, are
met. If so, the action is performed.  If the direction of the rule is
specified as "rightward", then the criterion-checking and rule execution
begin with the leftmost segment and proceed to the right.  If the direction
is "leftward", the opposite occurs: focus begins on the rightmost segment
and proceeds to the left.

=back

The crucial point is that the rule mechanism has focus on one segment at a
time, and that this focus proceeds across each available segment in turn.
Criterion checking and execution are done for every segment.

=head2 Using 'where' and 'do'

Of course, the actual criteria and execution are done by the coderefs that
you supply. So you have to know how to write reasonable criteria and
actions.

Lingua::Phonology::Rules will pass an array of segments to both of the
coderefs that you give it. This array of segments will be arranged so that
the segment that currently has focus will be at index 0, the following
segment will be at 1, and the preceding segment at -1, etc. The ends of the
"word" (or domain, if you're using domains) are indicated by special
segments that have the feature BOUNDARY, and no other features.

For example, let's say we had applied a rule to a simple four-segment word
like in the following example:

	# Assume you have a Symbols object $symbols with the default symbol set
	# loaded

	$b = $symbols->new_segment('b');
	$a = $symbols->new_segment('a');
	$n = $symbols->new_segment('n');
	$d = $symbols->new_segment('d');

	# Now, let's apply some rules to this word
	$rules->apply('MyRule', \($b, $a, $n, $d));

If MyRule applies rightward and there are no tiers or domains, then the
contents of @_ will be as follows on each of the four turns. (Boundary
segments are indicated by '$$'):

	         $_[-2]   $_[-1]   $_[0]   $_[1]   $_[2]   etc...
	
	turn 1    $$       $$       $b      $a      $n
	turn 2    $$       $b       $a      $n      $d
	turn 3    $b       $a       $n      $d      $$
	turn 4    $a       $n       $d      $$      $$

This makes it easy and intuitive to refer to things like 'current segment'
and 'preceding segment'. The current segment is $_[0], the preceding one is
$_[-1], the following segment is $_[1], etc.

(Yes, it's true that if the focus is on the first segment of the word,
$_[-3] refers to the last segment of the word. So be careful. Besides, you
should rarely, if ever, need to refer to something that far away. If you
think you do, then you're probably better off using a tier.)

Using our same example, then, we could write a rule that devoices final
consonants very easily.

	# Create the rule with two simple code references
	$final = sub { $_[1]->BOUNDARY };
	$devoice = sub { $_[0]->delink('voice') };
	$rules->add_rule(FinalDevoicing => { where => $final,
	                                     do    => $devoice });
	
	@word = ($b, $a, $n, $d);
	$rules->FinalDevoicing(\@word);
	print $symbols->spell(@word); # Prints 'bant'

It is recommended that you follow the intent of the design, and only use
the 'where' property to check conditions, and use the 'do' property to
actually affect changes. We have no way of enforcing this, however.

Note that, since the code in 'where' and 'do' simply operates on a local
subset of the segments that you provided as the word, doing something like
C<delete($_[0])> doesn't really have any effect. Yes, the local reference
to the segment at $_[0] is deleted, but the segment still exists outside of
the subroutine. Instead, write C<< $_[0]->clear >>, which removes all
feature settings from the segments. Lingua::Phonology::Rules will later
clear out any segments that have no features on them for you.

As a corollary, if you give segments that have no feature values set as
input, they will be silently dropped from the output.

=head2 Using tiers

Many linguistic rules behave transparently with respect to some segments or
classes of segments. Within the Rules class, this is accomplished by
setting the "tier" property of a rule.

The argument given to a tier is the name of a feature. When you specify a
tier for a rule and then apply that rule to an array of segments, the rule
will only apply to those segments that are defined for that feature. Note
that I said 'defined'--binary or scalar features that are set to 0 will
still appear on the tier.

This is primarily useful for defining rules that apply across many
intervening segments. For example, let's say that you have a vowel harmony
rule that applies across any number of intervening consonants. The best
solution is to specify that the rule has the tier 'vocoid'. This will cause
the rule to completely ignore all non-vocoids: non-vocoids won't even
appear in the array that the rule works on.

	# Make a rather contrived word
	@word = $symbols->segment('b','u','l','k','t','r','i'),

	# Note that if we were doing this without tiers, we would have to
	# specify $_[5] to see the final /i/ from the /u/. No such nonsense is
	# necessary when using the 'vocoid' tier, because the only segments
	# that the rule "sees" are ('u','i').
	
	# If the next segment is front ([-anterior] in the default feature set) . . .
	$where = sub { not $_[1]->anterior };

	# Then you also become front by copying the following segment's Lingual
	# values (see the Segment documentation and default feature set if this
	# makes no sense to you).

	$do = sub { $_[0]->Lingual( $_[1]->value_ref('Lingual') ) };

	# Make the rule, being sure to specify the tier
	$rules->add_rule( VowelHarmony => { tier => 'vocoid',
	                                    direction => 'rightward',
										where => $where,
										do => $do });
	
	# Apply the rule and print out the result
	$rules->VowelHarmony(\@word);
	print $symbols->spell(@word); # prints 'bylktri'

Tiers include one more bit of magic. When you define a tier, if consecutive
segments that are defined on that tier are references to the same value,
Lingua::Phonology::Rules will combine them into one segment before going to
execution. Once such a segment is constructed, you can assign or test
values for the tier feature itself, or any features that are children of
the tier (if the tier is a node). Assigning or testing other values will
generally fail and return undef, but it I<may> succeed if the return values
of the assignment or test are the same for every segment. Be careful.

This (hopefully) makes linguistic sense--if you're using the tier
'SYLLABLE', what you're really interested in are interactions between whole
syllables. So that's what you see in your rule: "segments" that are really
syllables and include all of the true segments inside them.

=head2 Using filters

Filters are a more flexible, but less magical, way of doing the same thing
that a tier does. You define a filter as a code reference, and all of the
segments in the input word are put through that code before going on to the
rule execution. Your code reference should accept a single
Lingua::Phonology::Segment object as an argument and return some sort of
truth value that determines whether the segment should be included.

A filter is a little like a tier and a little like a where, so here's how
it differs from both of those:

=over 4

=item *

Unlike a tier, the C<filter> property is a code reference. That means that
your test can be arbitrarily complex, and is not limited to simply testing
for whether a property is defined like a tier. On the other hand, there is
no magical combination of segments with a tier.

=item *

Unlike a C<where> property, a filter code reference only gets one segment
at a time. Therefore, you can't refer to adjacent segments when you're
writing the code reference for a filter. Also, the rule algorithm takes the
filter and goes over the whole word with it once, picking out those
segments that pass through the filter. It then hands the filtered list of
segments to be evaluated by C<where> and C<do>. A C<where> property is
evaluated for each segment in turn, and if the C<where> evaluates to true,
the C<do> code is immediately executed.

=back

Filters are primarily useful when you want to only see segments that meet a
certain binary or scalar feature value, or when you want to avoid the
magical segment-joining of a tier.

=head2 Using domains

Domains, like tiers, change the segments that are visible to your rules. A
domain, however, simply splits the word given to the rule into parts.

The value for a domain is the name of a feature. If the domain property is
specified for a rule, the input word given to the rule will be broken into
groups of segments whose value for that feature are references to the same
value. For the execution of the rule, those groups of segments act as
complete words with their own boundaries. For example:

	@word = $symbols->segment('b','a','r','d','a','m');

	# Syllable 1
	$word[0]->SYLLABLE(1);
	$word[1]->SYLLABLE($word[0]->value_ref('SYLLABLE'));
	$word[2]->SYLLABLE($word[0]->value_ref('SYLLABLE'));

	# Syllable 2
	$word[3]->SYLLABLE(1);
	$word[4]->SYLLABLE($word[3]->value_ref('SYLLABLE'));
	$word[5]->SYLLABLE($word[3]->value_ref('SYLLABLE'));

	# Make a rule to assign codas
	$rules->add_rule( Coda => { domain => 'SYLLABLE',
							     where => sub { $_[1]->BOUNDARY },
								 do => sub { $_[0]->coda(1) }});
	$rules->Coda(\@word);
	# Now both the /r/ and the /m/ are marked as codas

In this example, if we hadn't specified the domain 'SYLLABLE', only the /m/
would have been marked as a coda, because only the /m/ would have been at a
boundary. With the SYLLABLE domain, however, the input word is broken up
into the two syllables, which act as their own words with respect to
boundaries.

When using domains and tiers together, the word is broken up into domains
I<before> the tier is applied. Thus, two segments which might otherwise
have been combined into a single pseudo-segment on a tier will not be
combined if they fall into different domains.

=head2 Writing insertion and deletion rules

The arguments provided to the coderefs in C<where> and C<do> are in a
simple list, which means that it's not really possible to insert and delete
segments in the word from the coderef. Segments added or deleted in @_ will
disappear once the subroutine exits. Lingua::Phonology::Rules provides a
workaround for both of these cases.

Deletion can be accomplished by setting a segment to have no features set.
This is easily done with the clear() method for Segment objects. When the
coderef for C<where> or C<do> exits, any segments with no values will be
automatically delete. A rule deleting coda consonants can be written thus:

	# Assume that we have already assigned coda consonants to have the
	# feature 'coda'
	$rules->add_rule( DeleteCodaC => { where => sub { $_[0]->coda },
	                                    do => sub { $_[0]->clear });

As a side effect of this, if you provide input segments that have no
features set, they will be silently deleted from output.

Insertion can be accomplished using the special methods INSERT_RIGHT() and
INSERT_LEFT() on a segment. The argument to INSERT_RIGHT() or INSERT_LEFT()
must be a Segment object, which will be added to the right or the left of
the segment object on which the method is called. For example, the
following rule inserts a schwa to the left of a segment that is
unsyllabified:

	# Assume that we have a $symbols object defined with the default
	# feature set and that we've already applied a syllabification
	# algorithm that leaves some segments unparsed
	$rules->add_rule( Epenthesize => { where => sub { not $_[0]->SYLLABLE },
	                                   do => { $_[0]->INSERT_LEFT($symbols->segment('@'))});

Note that the methods INSERT_RIGHT() and INSERT_LEFT() don't exist except
inside the coderef for a rule.

=head2 Developer goodies

Theres a couple of things here that are probably of no use to the average
user, but have come in handywhen developing code for other modules or
scripts to use. And who knows, you may have a use for them.

First, any segment that has been inserted as part of the current rule will
have a property C<_NEW>. This property will disappear as soon as the
current rule finishes, so it is only useful if you want to know if a
segment has been inserted in the very recent past.

Second, all segments have the property C<_RULE> during the execution of a
rule. This method returns a hash reference that has keys corresponding to
the properties of the currently executing rule. These properties include
C<do, where, domain, tier, direction>, etc. If for some reason you need to
know or change one of these during the execution of a rule, you can use
this to do so. Note that altering the hash reference will alter the actual
properties of the current rule--although you won't notice it until the next
time the rule is executed.

Here's a silly example:

	sub print_direction {
		print $_[0]->_RULE->{direction}, "\n";
	}

	# Assume that we have $rules and @word lying around
	$rules->add_rule(
		PrintLeft => {
			direction => 'leftward',
			do => \&print_direction
		},
		PrintRight => {
			direction => 'rightward',
			do -> \&print_direction
		});
	
	$rules->PrintLeft(\@word);    # Prints 'leftward' several times
	$rules->PrintRight(\@word);   # Prints 'rightward' several times

=head1 TO DO

I'd like to provide a library of exportable functions that perform common
sorts of linguistic processes. Things like assimilate(), dissimilate(),
epenthesize(), delete(), metathesize(), syllabify(), etc. This perhaps
should go in a different module.

The handling of insertion and deletion is also very ad-hoc. Better
suggestions are welcome.

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
