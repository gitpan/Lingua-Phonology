#!/usr/bin/perl -w

package Lingua::Phonology::Features;

=head1 NAME

Lingua::Phonology::Features - a module to handle a set of hierarchical
features.

=head1 SYNOPSIS

	use Lingua::Phonology;

	my $phono = new Lingua::Phonology;

	my $features = $phono->features;
	$features->loadfile;                  # Load default features

=head1 DESCRIPTION

Lingua::Phonology::Features holds a list of hierarchically arranged 
features of various types, and includes methods for adding and deleting
features and changing the relationships between them.

By "heirarchical features" we mean that some features dominate some other
features, as in a tree. By having heirarchical features, it becomes 
possible to set multiple features at once by assigning to a node, and to
indicate conceptually related features that are combined under the same
node. However, the assignment of values to features is not handled by this
module--that's the job of Lingua::Phonology::Segment.

Lingua::Phonology::Features also recognizes multiple types of features.
Features may be privative (which means that their legal values are either true
or undef), binary (which means they may be true, false, or undef), or scalar
(which means that their legal value may be anything). You can freely mix
different kinds of features into the same set of features.

Finally, while this module provides a full set of methods to add and delete
features programmatically, it also provides the option of reading feature
definitions from a file. This is usually faster and more convenient. The 
method to do this is L<"loadfile">. Lingua::Phonology::Features also comes
with an extensive default feature set.

=cut

use strict;
use warnings;
use warnings::register;
use Carp;

our $VERSION = 0.2;

# Get Graph if present
our $GRAPH;
BEGIN {
	$GRAPH = eval 'use Graph; 1';
}

=head1 METHODS

=head2 new

This method creates and returns a new Features object. It takes no arguments.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { }; # $self can be a single-layer hash
	bless $self, $class;
	return $self;
} # end new

=head2 add_feature

Adds a new feature to the current list of features. Accepts a list of
arguments of the form "feature_name => { ... }", where the value assigned
to each feature name must be a hash reference with one or more of the
following keys:

=over 4

=item *

B<type> -- The type must be one of 'privative', 'binary', 'scalar', or
'node'.  The feature created is of the type specified. This key must be
defined for all features.

=item *

B<child> -- This is only relevant if the feature type is a node. The value
for this key is a reference to an array of feature names. The features
named will be assigned as the children of the feature being defined.

=item *

B<parent> -- The inverse of C<child>. The value for this key must be a 
reference to an array of feature names that are assigned as the parents
of the feature being added.

=back

Note that the features named in C<parent> or C<child> must already be
defined when the new feature is added. Thus, trying to add parents and
children as part of the same call to add_feature() will almost certainly
result in errors.

This method returns a list of all of the current features after new
features have been added.

Example:

	use Lingua::Phonology::Features;
	my $features = new Lingua::Phonology::Features;

	$features->add_feature( anterior => { type => 'binary' },
	                        distributed => { type => 'binary' });
	$features->add_feature( Coronal => { type => 'node', child => ['anterior', 'distributed']});

B<WARNING>: The following feature names are used by Lingua::Phonology::Rules
and should not be included as part of user feature sets: C<BOUNDARY, _RULE,
INSERT_RIGHT, INSERT_LEFT>. Also, the features C<SYLL, Rime, onset, nucleus,
coda, sonority> are used by Lingua::Phonology::Syllable. They may be defined as
part of a user feature set, but their original definitions may be overwritten.

=cut

# %valid defines valid feature types
our %valid = (	privative => 1,
				binary => 1,
				scalar => 1,
				node => 1
				);

sub add_feature {
	my $self = shift;
	my %hash = @_;

	# Do this for each key of the hashref you're given
	FEATURE: for (keys(%hash)) {
		# Check that the values for each key are also hashrefs
		if (ref($hash{$_}) ne 'HASH') {
			err("Bad value for $_");
			next FEATURE;
		} # end if

		# Carp if you're not given the type feature for each item	
		if (not $hash{$_}{type}) {
			err("No type given for feature '$_'");
			next FEATURE;
		} # end if

		# Check and carp if you're not given a proper type
		$hash{$_}{type} = lc $hash{$_}{type};
		if (not $valid{$hash{$_}{type}}) {
			err("Unrecognized type '$hash{$_}{type}' for feature $_");
			next FEATURE;
		} # end unless
		
		# If you've made it through above, add just the feature and type
		$self->{$_}->{type} = $hash{$_}{type};

		# The next section needs less strictness to avoid fatal errors when bad
		# arguments are passed
		no strict 'refs';

		# Handle children via add_child method
		err("Bad value for child of $_")
			if ($hash{$_}{child} && ref($hash{$_}{child}) ne 'ARRAY');
		for my $child (@{$hash{$_}{child}}) {
			$self->add_child($_, $child);
		} # end for

		# Handle parents via add_parent method
		err("Bad value for parent of $_")
			if ($hash{$_}{parent} && ref($hash{$_}{parent}) ne 'ARRAY');
		for my $parent (@{$hash{$_}{parent}}) {
			$self->add_parent($_, $parent);
		} # end for

	} # end for

	# Return the new list of features
	return keys(%$self);
} # end add_feature

=head2 feature

Given the name of a feature, returns a hash reference showing the current
settings for that feature. The hash reference will at least contain the
key 'type', naming the feature type, and may contain the key 'child' if
the feature is a node.

=cut

sub feature {
	my $self = shift;
	my $feature = shift;
	return $self->{$feature} if exists($self->{$feature});
	return err("No such feature '$feature'");
} # end feature

=head2 feature_exists 

Given the name of the feature, returns a simple truth value indicating whether
or not any such feature with that name currently exists. Unlike feature(), this
method never gives an error, and does not return the feature reference on
success. This can be used by programs that want to quickly check for the
existence of a feature without the possibility of errors.

=cut

sub feature_exists {
	my $self = shift;
	return exists $self->{$_[0]};
}

=head2 drop_feature

Given the name of a feature, deletes the given feature from the current
list of features. Note that deleting a node feature does not cause its
children to be deleted--it just causes them to revert to being
undominated. This method always returns true.

=cut

sub drop_feature {
	my $self = shift;
	delete($self->{$_}) for @_;
	return 1; # always return true
} # end drop_feature

=head2 change_feature

This method works identically to add_feature(), but it first checks to see
that the feature being changed already exists. If it doesn't, it will give
an error. If every attempted change given to this function succeeds, then
this method returns 1. Otherwise, it returns 0.

The add_feature() method can also be used to change existing features--this
method exists only to aid readability.

=cut

sub change_feature {
	my $self = shift;
	my %hash = @_;
	my $return = 1;

	FEATURE: for (keys(%hash)) {
		# Check that there is such a feature
		if (not $self->feature($_)) {
			$return = 0;
			next FEATURE;
		}

		# Pass the buck to add_feature
		$self->add_feature($_ => $hash{$_}) or $return=0;
	} # end for
	return $return;
} # end change_feature

=head2 all_features

Takes no arguments. Returns a hash with feature names as its keys, and the
parameters for those features as its values.

=cut

sub all_features {
	my $self = shift;
	return %$self;
} # end all_features

=head2 loadfile

Takes one argument, the path and name of a file. Reads the lines of the
file and adds all of the features defined therein. You can also call this
method with no arguments, in which case the default feature set is loaded.

Feature definition lines should be in this format:

	feature_name   [1 or more tabs]   type   [1 or more tabs]   children (separated by spaces)

You can order your features any way you want in the file. The method will
take care of ensuring that parents are defined before their children are
added and make sure no conflicts result.

Lines beginning with a '#' are assumed to be comments are are skipped.

If you don't provide any arguments to this feature, then the default
feature set is read and loaded. The default feature set is described in
L<"THE DEFAULT FEATURE SET">.

=cut

# Load feature definitions from a file
sub loadfile {
	my $self = shift;
	my $file = shift;

	no strict 'refs';
	if ($file) {
		open $file, $file or return err("Couldn't open $file: $!");
	}
	else {
		# $file = Lingua::Phonology::Default::open('features');
		$file = 'DATA';
	} # end if/else

	my (%children, %symbols);
	while (<$file>) {
		if (/^\s*([^#]\w+)\t+(\w+)(\t+(.*))?/) {
			my ($name, $type, $children) = ($1, $2, $4);
			@{$children{$name}} = split(/\s+/, $children) if ($children);

			# Immediately add feature names
			$self->add_feature($name => {type => $type});
		} # end if

	} # end while

	# Now add children
	for (keys(%children)) {
		$self->add_child($_, @{$children{$_}});
	} # end for
	
	if ($file eq 'DATA') {
		seek $file, 0, 0;
	}
	else {
		close $file;
	}
	return 1;

} # end loadfile

=head2 children

Takes one argument, the name of a feature. Returns a list of all of the
features that are children of the feature given.

=cut

sub children {
	my $self = shift;
	my $feature = shift;
	my $featureref = $self->feature($feature) or return undef;

	return @{$featureref->{child}} if ($featureref->{child}); # return a real array
	return (); # Empty array otherwise
} # end children

=head2 add_child

The first argument to this method should be the name of a node-type
feature.  The remaining arguments are the names of features to be assigned
as children to the first feature. If all children are added without errors,
this function returns 1. Otherwise it returns false.

=cut

sub add_child {
	my $self = shift;
	my $parent = shift;
	my $parentref = $self->feature($parent) or return undef;
	my $return = 1;

	# Check that the parent is a node
	return err("$parent is not a node") if ($parentref->{type} ne 'node');

	CHILD: for my $child (@_) {
		# Check that the child feature exists
		if (not $self->feature($child)) {
			$return = 0;
			next CHILD;
		}

		# Check that you haven't already defined this child
		for (@{$parentref->{child}}) {
			if ($child eq $_) {
				err("$child is already child of $parent");
				next CHILD;
			} # end if
		} # end for

		# If you get this far, you're good to go
		push(@{$parentref->{child}}, $child);
	} # end for

	return $return;
} # end sub

=head2 drop_child

Like add_child, the first argument to this function should be the name of a
node feature, and the remaining arguments are the names of children of that
node. The child features so named will be deleted from the list of children
for that node. This function returns a hash reference for the parent
feature, showing the modifications to its C<child> key that have just been
made, except when no such feature exists, in which case it gives an error.

=cut

sub drop_child {
	my $self = shift;
	my $parent = shift;
	my $parentref = $self->feature($parent) or return undef;

	for my $child (@_) {
		for (0 .. $#{$parentref->{child}}) {
			delete($parentref->{child}->[$_]) if $parentref->{child}->[$_] eq $child;
		} # end for
	} # end for
	return $parentref;
} # end drop_child

=head2 parents

Takes one argument, the name of a feature. Returns a list of the current
parent nodes of that feature.

=cut

sub parents {
	my $self = shift;
	my $feature = shift;
	
	my @parents;
	my %features = $self->all_features;
	for my $parent (keys(%features)) {
		for ($self->children($parent)) {
			push (@parents, $parent) if ($feature eq $_);
		} # end for
	} # end for

	return @parents; 
} # end parents

=head2 add_parent

Takes two or more arguments. The first argument is the name of a feature,
and the remaining arguments are the names of nodes that should be parents
of that feature. Returns true if all of the attempted operations succeeded,
otherwise returns false. Note that a false return does not mean that all
operations failed, only some.

=cut

sub add_parent {
	my $self = shift;
	my $child = shift;
	my $return = 1;

	# This action is identical to add_child, but with order of arguments switched
	# So just pass the buck
	for (@_) {
		$self->add_child($_, $child) or $return = 0;
	} # end for
	return $return;
} # end add_parent

=head2 drop_parent

Takes two or more arguments. The first is a feature name, and the remaining
arguments are the names of features that are currently parents of that
feature. Those features will cease to be parents of the first feature. This
feature always returns a hash reference giving the properties of the child
feature.

=cut

sub drop_parent {
	my $self = shift;
	my $child = shift;
	my @parents = @_;

	# Once again, just pass to drop_child
	for (@parents) {
		$self->drop_child($_, $child);
	} # end for
	return $self->feature($child);
} # end drop_parent

=head2 graph

Takes no arguments. Returns an object in class Graph indicating the structure
of the current Lingua::Phonology::Features object. You may use this graph for
printing or other analysis.

You must have the Graph module installed for this function to work. If you do
not have Graph installed, you will get an error.

=cut

sub graph {
	# Bail if we don't have Graph
	if (not $GRAPH) {
		carp "Can't call graph: Graph module not available";
		return undef;
	}

	my $self = shift;

	my $g = new Graph;
	for my $feature (keys %$self) {
		$g->add_vertex($feature);
		$g->set_attribute('type', $feature, $self->type($feature));
		for ($self->children($feature)) {
			$g->add_edge($feature, $_);
		}
	}

	return $g;
}

=head2 type

Takes one or two arguments. The first argument must be the name of a 
feature. If there is only one argument, the type for that feature is
return. If there are two arguments, the type is set to the second 
argument and returned.

=cut

sub type {
	my $self = shift;
	my $feature = shift;
	my $type = shift;
	my $featureref = $self->feature($feature);

	# Check that this is a real feature
	return undef unless $featureref;

	# With two arguments, set the type
	if ($type) {
		# Check for valid types
		return err("Invalid type $type") if (not $valid{$type});

		# Otherwise:
		$featureref->{type} = $type;
	} # end if
	
	# Return the current type
	return $featureref->{type};
} #end sub

=head2 number_form

Takes two arguments. The first argument is the name of a feature, and the
second is a value to be converted into the appropriate numeric format
for that feature. The conversion from input value to numeric value depends
on what type of feature the feature given in the first argument is. A few
general text conventions are recognized to make text parsing easier and
to ensure that number_form and L<"text_form"> can be used as inverses of
each other. The conversions are as follows:

=over 4

=item *

The string '*' is recognized as a synonym for C<undef> in all circumstances.
It always returns C<undef>.

=item *

B<privative> features return 1 if given any true true value, else C<undef>.

=item *

B<binary> features return 1 in the case of a true value, 0 in case of a 
defined false value, and otherwise C<undef>. The string '+' is a synonym for
1, and '-' is a synonym for 0. Thus, the following two lines both return
0:

	print $features->number_form('binary_feature', 0); # prints 0
	print $features->number_form('binary_feature', '-'); # prints 0

However, if the feature given is a privative feature, the first returns
C<undef> and the second returns 1.

=item *

B<scalar> features return the value that they're given unchanged (unless 
that value is '*', which is translated to C<undef>).

=item *

B<node> features do not have values of their own, but should be hash 
references containing the values for their children. Therefore, nodes
return C<undef> for anything other than a hash ref, and return hash refs
unchanged.

=back

=cut

# The following coderefs exist in a hash for each feature type defined
our %num_form = (
	privative => sub {
		return 1 if $_[0];
		return undef;
	},
	binary =>sub {
		my $value = shift;
		# Text values
		return 0 if ($value eq '-');
		return 1 if ($value eq '+');
		# If not given a text value
		return 1 if ($value);
		return 0;
	},
	scalar => sub {
		return $_[0]; # Nothing happens to scalars
	},
	node => sub {
		return undef if ref($_[0]) ne 'HASH'; # Nodes should be hashrefs
		return $_[0];
	}
);

sub number_form {
	my $self = shift;

	# Check number of arguments
	return err("Not enough arguments to number_form") if ($#_ < 1);

	# Otherwise, take your args
	my $feature = shift;
	my $value = shift;
	
	# Return bad features
	my $ref = $self->feature($feature) or return undef;

	# undef is always valid
	# '*' is always a synonym for undef
	return undef if (not defined($value));
	return undef if ($value eq '*');

	# Otherwise, pass processing to the appropriate coderef
	return &{$num_form{$ref->{type}}}($value);
} # end number_form 

=head2 text_form

This function is the inverse of number_form. It takes two arguments, a 
feature name and a numeric value, and returns a text equivalent for the
numeric value given. The exact translation depends on the type of the 
feature given in the first argument. The translations are:

=over 4

=item *

Any undefined value or the string '*' returns '*'.

=item *

B<privative> features return '*' if undef or logically false, otherwise '' (an empty string).

=item *

B<binary> features return '+' if true, '-' if false or equal to '-', and '*' if
undefined.

=item *

B<scalar> features return their values unchanged, except for if they're
undefined, in which case they return '*'.

=item *

B<node> features behave the same as privative features in this function.

=back

=cut

# Code references

our %text_form = (
	privative => sub {
		return '';
	},
	binary => sub {
		return '+' if shift;
		return '-';
	},
	scalar => sub {
		return shift;
	},
	node => sub {
		return '';
	}
);

sub text_form {
	my $self = shift;

	# Check number of arguments
	return err("Not enough arguments to text_form") if ($#_ < 1);

	# Otherwise, take your args
	my $feature = shift;
	my $value = shift;
	
	# Return bad features
	my $ref = $self->feature($feature) or return undef;

	# first mash through number_form
	$value = $self->number_form($feature, $value);
	# '*' is always a synonym for undef
	return '*' if (not defined($value));

	return &{$text_form{$ref->{type}}}($value);
} # end text_form

# A very short error writer
sub err {
	carp shift if warnings::enabled();
	return undef;
} # end err

1;

=head1 THE DEFAULT FEATURE SET

If you call the method C<L<"loadfile">> without any arguments, like this:

	$features->loadfile

then the default feature set is loaded. The default feature set is a
feature geometry tree based on Clements and Hume (1995), with some
modifications. This set gratuitously mixes privative, binary, and scalar
features, and may or may not be actually useful to you.

Within this feature set, we use the convention of putting top-level
(undominated) nodes in ALL CAPS, putting intermediate nodes in Initial
Caps, and putting terminal features in lowercase. The feature tree created
is:

	# True features
	ROOT
	 |
	 +-sonorant privative
	 +-approximant privative
	 +-vocoid privative
	 +-nasal privative
	 +-lateral privative
	 +-continuant binary
	 +-Laryngeal
	 |  |
	 |  +-spread privative
	 |  +-constricted privative
	 |  +-voice privative
	 |  +-ATR binary
	 |
	 +-Place
	    |
	    +-pharyngeal privative
		+-Oral
		   |
		   +-labial privative
		   +-Lingual
		   |  |
		   |  +-dorsal privative
		   |  +-Coronal
		   |     |
		   |     +-anterior binary
		   |     +-distributed binary
		   |
		   +-Vocalic
		      |
		      +-aperture scalar
			  +-tense privative
			  +-Vplace
			     |
			     +-labial (same as above)
				 +-Lingual (same as above)
	
	# Features dealing with syllable structure
	# These are capitalized as if they were in a heirarchy (for
	# readability), though properly they don't dominate each other
	SYLLABLE privative
	onset privative
	Rime privative
	nucleus privative
	coda privative

=head1 TO DO

Improve the default feature set. As it is, it cannot handle uvulars or
pharyngeals, and has some quirks in its relationships that lead to strange
results. Though some of this is the fault of phonologists who can't make up
their minds about how things are supposed to go together.

=head1 SEE ALSO

Lingua::Phonology::Segment, Lingua::Phonology::Rules

=head1 REFERENCES

Clements, G.N and E. Hume. "The Internal Organization of Speech Sounds."
Handbook of Phonological Theory. Ed. John A. Goldsmith. Cambridge,
Massachusetts: Blackwell, 2001. 245-306.

This article is a terrific introduction to the concept of feature geometry,
and also describes ways to write rules in a feature-geometric system.

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@u.washington.edu>>.

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut

__DATA__

# Definition of true features, concerned with articulation of segments
ROOT		node		sonorant approximant vocoid nasal lateral continuant Laryngeal Place
sonorant	privative
approximant	privative
vocoid		privative
nasal		privative
lateral		privative
continuant	binary

Laryngeal	node		spread constricted voice ATR
spread		privative
constricted	privative
voice		privative
ATR			binary

Place		node		pharyngeal Oral
pharyngeal	privative

Oral		node		labial Lingual Vocalic
labial		privative

Lingual		node		Coronal dorsal
dorsal		privative

Coronal		node		anterior distributed
anterior	binary
distributed	binary

Vocalic		node		Vplace aperture tense
aperture	scalar
tense		binary
Vplace		node		labial Lingual

# Definition of syllable-related features, used for parsing syllables
# These aren't truly heirarchical, to allow for proper domaining
SON			scalar
SYLL		scalar
Rime		privative
onset		privative
nucleus		privative
coda		privative

__END__
