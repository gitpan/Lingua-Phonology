#!/usr/bin/perl -w

package Lingua::Phonology::Segment;

=head1 NAME

Lingua::Phonology::Segment - a module to represent a segment as a bundle
of feature values.

=head1 SYNOPSIS

	use Lingua::Phonology;
	$phono = new Lingua::Phonology;

	# Define a feature set
	$features = $phono->features;
	$features->loadfile;

	# Make a segment
	$segment = $phono->segment;

	# Set some values
	$segment->labial(1);
	$segment->continuant(0);
	$segment->voice(1);  # Segment is now voiced labial stop, i.e. [b]

	# Reset the segment
	$segment->clear;

=head1 DESCRIPTION

A Lingua::Phonology::Segment object provides a programmatic representation
of a linguistic segment. Such a segment is associated with a
Lingua::Phonology::Features object that lists the available features and
the relationships between them. The segment itself is a list of the values
for those features. This module provides methods for returning and setting
these feature values. A segment may also be associated with a
Lingua::Phonology::Symbols object, which allows the segment to return the
symbol that it best matches. 

=cut

use strict;
use warnings;
use warnings::register;
use Carp;
use Lingua::Phonology::Features;

our $VERSION = 0.2;

=head1 METHODS

=head2 new

Takes one argument, a Lingua::Phonology::Features object. The Features 
object provides the list of available features. If no such object is
provided, this method will carp and return undefined.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { FEATURES => undef,
				 SYMBOLS => undef,
				 VALUES   => { } };
	
	my $featureset = shift; # An object in class Features
	my $values = shift; # A hashref

	# Require a $featureset of the proper type
	return err("No featureset (or bad featureset) given for new $class") if (not UNIVERSAL::isa($featureset, 'Lingua::Phonology::Features'));

	# Set your featureset
	$self->{FEATURES} = $featureset;

	# Gesundheit
	bless $self, $class;

	# Set initial values
	for (keys(%$values)) {
		$self->value_ref($_, $values->{$_});
	} # end for

	return $self;
} # end new

=head2 featureset

Returns the Features object currently associated with the segment. May be
called with one argument, a Features object, in which case the current 
feature set is set to the object provided.

=cut

sub featureset {
	my $self = shift;
	if (@_) {
		$self->{FEATURES} = shift if (UNIVERSAL::isa($_[0], 'Lingua::Phonology::Features'));
		err("Bad feature set or too many arguments") if @_;
	}
	return $self->{FEATURES};
} # end featureset

=head2 symbolset

Returns a Symbols object currently associated with the segment. You may
call this method with one argument, in which case the symbol set is set to
that argument.

=cut

sub symbolset {
	my $self = shift;
	if (@_) {
		$self->{SYMBOLS} = shift if (UNIVERSAL::isa($_[0], 'Lingua::Phonology::Symbols'));
		err("Bad symbol set or too many arguments") if @_;
	}
	return $self->{SYMBOLS};
} # end symbolset

=head2 value

Takes one or two arguments. The first argument must be the name of a 
feature. If only one argument is provided, this method simply returns the
value that the segment currently has for that feature. If there is a 
second argument, the value for the feature is set to that argument.

If you are attempting to set a value, the value will first be passed 
through Lingua::Phonology::Features::number_form(), and stored in its 
numeric form. See L<features/"number_form"> for an explanation of how this
conversion works. Conversely, values returned from this function have 
already been passed through number_form() and may differ significantly
(though predictably) from the values originally passed in.

You may also pass a scalar reference to value(), in which case the value
for the segment is set to the value that the reference points to. This has
other side effects, though. See the description of L<"value_ref"> for an 
explanation of why and how this works.

Values for nodes (features which are parents of other features) are 
different from the values for terminal features. A node has no value of 
its own; rather, its value is the aggregate of the values of its children.
Therefore, the value returned from a node is a hash reference, the keys of
which are features for children that have a defined value. The values of
the hash ref are the values associated with those features (which may in 
turn be hash references, etc.). A node that has no defined children 
returns undef.

Conversely, the second argument to value() must be a hash reference if the
feature you are assigning to is a node. When you assign a hash reference to
a node in this way, keys not present in the hash are not affected.
Therefore, assigning an empty hash to a node does NOT cause the node to be
deleted, as might be expected, but rather has not affect at all. For
example:

	# Both sonorant and vocoid are children of ROOT

	$segment->value('sonorant', 1);   
	# Now the value for ROOT is { sonorant => 1 }

	$segment->value('ROOT', { vocoid => 1 });
	# Now the value for ROOT is { sonorant => 1, vocoid => 1 }
	
	$segment->value('ROOT', {});
	# The value for ROOT is still { sonorant => 1, vocoid => 1 }

To delete a node, use the method L<"delink"> instead.

=cut

sub value {
	my $self = shift;
	return _deref($self->value_ref(@_));
} # end value

sub _deref {
	my ($ref, $code, $feature) = @_;
	$$ref = undef if not ref $ref;
	$code = sub { $_[1] } if not $code;

	if (ref($ref) eq 'SCALAR' || ref($ref) eq 'REF') {
		return &$code($feature, $$ref);
	}
	elsif (ref($ref) eq 'HASH') {
		%$ref = map { $_ => _deref($ref->{$_}, $code, $_) } keys %$ref;
	}
	return $ref;
} #end _deref

=head2 value_text

This method is equivalent to value(), and takes the same arguments.
However, the return from value() is first passed through the text_form()
function of Lingua::Phonology::Features and then returned. For details on
this conversion see L<features/"number_form">.

=cut

sub value_text {
	my $self = shift;
	return _deref($self->value_ref(@_), sub { $self->{FEATURES}->text_form(@_) }, $_[0]);
} # end value_text

=head2 value_ref

This method is identical in arguments to value(), taking a feature name as
the first argument and a value as the optional second argument. However, 
it returns a scalar reference rather than a real value.

Internally, all of the values for a Segment object are stored as scalar
references rather than direct values. When you call value(), all of the 
referencing and dereferencing is done for you, so you never have to think
about this. However, at times it may be useful to cause two or more 
Segments to have references to the same value, in which case you may use
the value_ref() method to return the reference from one of the objects.
If the value that you give to value(), value_text(), or value_ref() is a
scalar reference, then rather than setting the value via the current 
reference, the current reference will be replaced by the reference you
provided. This can cause two segments to "share" a feature, so that 
changes made to one segment automatically appear on the other. This
example should make things clearer:

	# Assume you have a Lingua::Phonology::Features object called $features with the default feature set
	$seg1 = Lingua::Phonology::Segment->new($features);
	$seg2 = Lingua::Phonology::Segment->new($features);

	# If we assign direct values, the segments can vary independently
	$seg1->value('voice', 1); 
	$seg2->value('voice', $seg1->value('voice'));	  # $seg2->value('voice') also returns 1
	$seg1->value('voice', 0);                         # now $seg1 return 0 for voice, but $seg2 returns 1

	# If we assign references, then the segments are linked to each other for that value
	$seg1->value('voice', 1');
	$seg2->value('voice', $seg1->value_ref('voice')); # $seg2 now returns 1 for voice
	$seg1->value('voice', 0);                         # now both $seg1 and $seg2 return 0 for voice

	# To break the connection between segments, pass one of them a reference to a literal value
	$seg1->value('voice', \1);                        # Now $seg1 returns 1, and $seg2 returns 0

As this example illustrates, any of the value_*() functions can be passed
any kind of argument (numeric, textual, or reference). The functions only
differ in what their return value is.

=head2 Calling feature names as methods

You can also return and set values to a segment by using the name of a 
feature as a method. This is usually easier and more readable that using
value(). The following are exactly synonymous:

	$seg1->value('voice', 1);
	$seg1->voice(1);

Calling a feature-name method like this is always equivalent to calling
value(), and never equivalent to calling value_text() or value_ref().

WARNING: If you use a feature name that is the same as a reserved word
(function or operator) in Perl, you can cause a non-terminating loop, due
to the implementation of autoloaded functions. Use the longer form with
value() instead.

=cut

sub _term_handler {
	my ($self, $feature, $value) = @_;

	# If we have a plain scalar ref, assign it directly
	if (ref($value) eq 'SCALAR') {
		# Check that the referred value is good
		$$value = $self->{FEATURES}->number_form($feature, $$value);
		# Assign
		$self->{VALUES}->{$feature} = $value;
	} # end if

	# Otherwise, assign the value via the current ref
	else {
		$value = $self->{FEATURES}->number_form($feature, $value);

		# If this feature is already defined, assign via the ref
		if (my $ref = $self->{VALUES}->{$feature}) {
			$$ref = $value;
		} # end if
		
		# If it's not defined, assign the value directly as a ref
		else {
			$self->{VALUES}->{$feature} = \$value;
		} # end else

	} # end else

} # end $term_handler
		
# Handle nodes
sub _node_handler {
	my ($self, $featureref, $value) = @_;

	# Make sure you're given a hashref
	return err("Value assigned to node not a hashref") unless (ref($value) eq 'HASH');

	for my $child (@{$featureref->{child}}) {
		# Assign values to all children
		$self->value_ref($child, $value->{$child}) if exists($value->{$child});
	} # end for
} # end $node_handler
		
sub value_ref {
	my $self = shift;
	my $feature = shift; # A string name of a feature
	my $featureref = $self->{FEATURES}->feature($feature) or return undef;

	# Node or terminal feature?
	if ($featureref->{type} eq 'node') {
		# Set values
		$self->_node_handler($featureref, shift()) if @_;

		# Build return hashref
		my $hashref = {};
		for my $child ($self->{FEATURES}->children($feature)) {
			my $val = $self->value_ref($child);
			$hashref->{$child} = $val if defined $val;
		} # end for
		return $hashref if keys %$hashref;
		return undef; # if the hash has no keys
	} # end if

	else {
		# Set values
		$self->_term_handler($feature, shift()) if @_;

		# Return value
		return $self->{VALUES}->{$feature};
	} # end else
				
} # end value_ref

=head2 delink

Takes a list of arguments, which are names of feature, and removes the
values for those features from the segment. The values for those features
will subsequently be undefined. This method does not affect the value that
the internal reference points to, so other segments that may be pointing to
the same value are unaffected. For example:

	$seg1->voice('1);
	$seg2->voice($seg1->value_ref('voice')); # $seg1 and $seg2 refer to the same value

	$seg2->voice(undef);                     # now both $seg1 and $seg2 will return 'undef' for voice

	$seg1->voice(1);                         # both will now return 1
	$seg2->delink('voice');                  # now $seg2 returns 'undef', but $seg1 returns 1

As an additional effect, the hash returned from L<"all_values">() will
include a key-value pair like C<< voice => undef >> if you assign an undef to
a value, as in line 4 above, while if you use delink(), no key for the 
deleted feature will appear at all.

Calling delink() on a node causes all children of the node to be delinked
recursively. This is the only way to clear a node in one step.

In scalar context, this method returns the number of items that were
delinked. In list context, it returns a list of the former values of the
features that were delinked. If you are delinking a node you will get a
list of the values of the children of that node, in a consistent but not
predictable order.

=cut

sub delink {
	my $self = shift;
	my @return = ();
	for (@_) {
		if ($self->{FEATURES}->type($_) eq 'node') {
			push @return, $self->delink($_) for ($self->{FEATURES}->children($_));
		}
		else {
			push @return, delete($self->{VALUES}->{$_});
		}
	}
	return @return;
} # end delink

=head2 all_values

Takes no arguments. Returns a hash with feature names as its keys and 
feature values as its values. The feature names present in the hash will
be those that have defined values for the segment, or those features that
were explicitly set to be undef (as opposed to being C<delink>ed).

=cut

sub all_values {
	my $self = shift;
	my %return;

	# Get the real values for each feature
	for (keys(%{$self->{VALUES}})) {
		# This could break if we change the way values are stored
		# But it's much faster than calling value() for each feature
		$return{$_} = ${$self->{VALUES}->{$_}};
	} # end for

	return %return;
} # end all_values

=head2 spell

Takes no arguments. Returns a text string indicating the symbol that the
current segment best matches if a Lingua::Phonology::Symbols object has
been defined via symbolset(). Otherwise returns an error.

=cut

sub spell {
	my $self = shift;
	# normal case
	return $self->{SYMBOLS}->spell($self) if $self->{SYMBOLS};
	
	# else
	return err("Can't call spell()--no symbol set defined");
}

=head2 duplicate

Takes no arguments. Returns a new Lingua::Phonology::Segment object that is
an identical copy of the current object.

=cut

sub duplicate {
	my $self = shift;
	my %values = $self->all_values;
	my $new = $self->new($self->featureset, \%values);
	return $new;
} # end duplicate

=head2 clear

Takes no arguments. Clears all values from the segment. Calling
L<"all_values">() after calling clear() will return an empty hash.

=cut

sub clear {
	my $self = shift;
	$self->{VALUES} = {};
} # end clear

# Allows you to call changes to feature settings directly
# with syntax like $segment->feature_name($value)
our $AUTOLOAD;
sub AUTOLOAD {
	my $feature = $AUTOLOAD;
	$feature =~ s/.*:://;

	# Compile functions which are features
	eval qq! sub $feature {
		my \$self = shift;
		\$self->value($feature, \@_);
		} # end sub
	!;

	no strict 'refs';
	goto &$feature;
} # end AUTOLOAD

sub DESTROY {} # To avoid catching DESTROY in AUTOLOAD

# A very short error writer
sub err {
	carp shift if warnings::enabled();
	return undef;
} # end err

1;

=head1 BUGS

The current method for handling suprasegmental features is ugly and
hackish. Something new should be come up with.

=head1 SEE ALSO

Lingua::Phonology::Features, Lingua::Phonology::Symbols

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
