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

This module allows for the creation of linguistic rules, and the application of
those rules to "words" of Segment objects. You, the user, add rules to a Rules
object, defining various parameters and code references that actually perform
the action of the rule. Lingua::Phonology::Rules will take care of the guts of
applying and creating rules.

The rules you create may have the following parameters. This is just a brief
description of the parameters--a more detailed discussion of their effect is in
the L<"WRITING RULES"> section.

=over 4

=item *

B<domain> - defines the domain within which the rule applies. This should be
the name of a feature in the featureset of the segments which the rule is
applied to.

=item *

B<tier> - defines the tier on which the rule applies. Must be the name of a
feature in the feature set for the segments of the word you pass in.

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

=item * 

B<result> - EXPERIMENTAL. Defines a condition that must be true after the C<do>
code has applied. Must be a code reference that returns a truth value. B<NOTE>:
This parameter depends on the module Whatif (available from CPAN), and will
behave differently if this module is not present. See L<"Using result">.

=back

Lingua::Phonology::Rules is flexible and powerful enough to handle any 
sequential type of rule system. It cannot handle Optimality Theory-style
processes, because those require a fundamentally different kind of 
algorithm.

=cut

use strict;
use warnings;
use warnings::register;
use Carp;
use Lingua::Phonology::Common;
use Lingua::Phonology::Segment::Rules;
use Lingua::Phonology::Segment::Boundary;
use Lingua::Phonology::Segment::Tier;
# use Whatif if it's available
BEGIN {
	eval 'sub whatif (&;$) {}' if not eval 'use Whatif; 1';
}

our $VERSION = 0.3;

sub err ($) { warnings::warnif(shift); return; }

# Define valid properties for rules, name => default format. undef's for no default
our %property = (
	where => sub {1},
  	do	=> sub {},
	tier  => undef,
	filter => undef,
	result => undef,
	domain => undef,
	direction => 'rightward'
);

# Hash of property => validating coderef
our %valid = (
    where => sub { _is($_[0], 'CODE') },
    do => sub { _is($_[0], 'CODE') },
    filter => sub { _is($_[0], 'CODE') },
    result => sub { _is($_[0], 'CODE') },
    tier => sub {1},
    domain => sub {1},
    direction => sub { $_[0] = lc $_[0]; ($_[0] eq 'leftward') or ($_[0] eq 'rightward') }
);

# Additional arrays that list properties expecting code and text respectively
our @code = qw/where do filter result/;
our @text = qw/tier domain direction/;

# Build accessors for properties
foreach my $method (keys %property) {
    no strict 'refs';
    *$method = sub {
        my $self = shift;
        my $rule = shift;
        if (@_) {
            # When defined, check for validity and add
            if (defined $_[0]) {
                if ($valid{$method}->($_[0])) {
                    $self->{RULES}->{$rule}->{$method} = $_[0];
                }
                else {
                    return err "Bad argument to $method()";
                }
            }
            # Otherwise, delete the key
            else {
                delete $self->{RULES}->{$rule}->{$method};
            }
        }
        return $self->{RULES}->{$rule}->{$method};
    };
}

# The same BOUNDARY seg is used by all instances (since all are alike)
our $BOUNDARY = Lingua::Phonology::Segment::Rules->new(Lingua::Phonology::Segment::Boundary->new());

# Constructor
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {
        RULES => { }, # list of rules
        ORDER => [ ], # rule order
        PERSIST => [ ], # list of persistent rules
        COUNT => 0, # count of times a rule applied, set by apply or apply_all
	};
	bless ($self, $class);
	return $self;
} 

# Add a rule. Called as $rules->add_rule( Name => { ... } );
sub add_rule {
	my ($self, %rules) = @_;
	my $err = 0;

	RULE: for my $rule (keys(%rules)) {
        # Check rules or complain
        $self->_check_rule($rules{$rule}) or do {
            $err = 1;
            next RULE;
        };

        # Drop existing rules
        $self->drop_rule($rule);

        # Add new rules
        $self->_add_rule($rule, $rules{$rule});

	} 
	return $err ? () : 1;
} 

# Drop a rule
sub drop_rule {
    my $self = shift;
    delete $self->{RULES}->{$_} for @_;
    return scalar @_;
}

# Like add_rule, but check that the rule exists
sub change_rule {
    my ($self, %rules) = @_;
    my $err = 0;

    RULE: for my $rule (keys %rules) {
        # Complain when the rule doesn't exist
        if (not exists $self->{RULES}->{$rule}) {
            err("No such rule '$rule'");
            $err = 1;
            next RULE;
        }

        # Check rules
        $self->_check_rule($rules{$rule}) or do {
            $err = 1;
            next RULE;
        };

        # Add rules
        $self->_add_rule($rule, $rules{$rule});
    }
    return $err ? () : 1;
}

sub _check_rule {
    my ($self, $href) = @_;
    for (keys %$href) {
        if (exists $valid{$_}) {
            unless ($valid{$_}->($href->{$_})) {
                return err("Invalid value for $_");
            }
        }
    }
    return 1;
}

sub _add_rule {
    my ($self, $rule, $href) = @_;

    $self->{RULES}->{$rule} = {};
    for (keys %property) {
        $self->$_($rule, $href->{$_} || $property{$_});
    }
}

sub clear {
	my $self = shift;
	$self->{RULES} = {};
	$self->{ORDER} = [];
	$self->{PERSIST} = [];
	return 1;
} 

sub loadfile {
	my ($self, $file) = @_;

    # Calling loadfile() w/o a file loads a default, but there is no default
    # rule set. So do nothing and return true.
    return 1 if not defined $file;

    my $parse;
    eval { $parse = _parse_from_file($file, 'rules') };
    return err $@ if $@;
    $self->_load_from_struct($parse);
}

sub _load_from_struct {
    my ($self, $parse) = @_;
	my $err = 0;

	# Handle rule declarations
	RULE: for my $href (@{$parse->{rule}}) {
		my $parm = {};

        # If we ONLY have content, make it into a href
        if (not _is($href, 'HASH')) {
            $href = { content => $href };
        }

        # Take linguistic-style rules from the content
        if (exists $href->{content}) {
            # _parse_ling() returns where and do
			($href->{where}, $href->{do}) = _parse_ling($href->{content});
		}

		# Iterate over elements
        # code elements
        for (@code) {
            next if not exists $href->{$_};

            # If we ONLY have content
            if (not _is $href->{$_}, 'HASH') {
                $href->{$_} = { content => $href->{$_} };
            }

            if ((not exists $href->{$_}->{type}) || $href->{$_}->{type} ne 'plain') {
                eval { $parm->{$_} = _parse_ext $href->{$_}->{content} };
            }
            else {
                eval { $parm->{$_} = _parse_plain $href->{$_}->{content} };
            }
            
            # Always check $@ after parsing
            if ($@) {
                err("Error processing rule $href->{name}: $@\n");
                $err = 1;
                next RULE;
            }
        }
        # text elements
        for (@text) {
            next if not exists $href->{$_};
            $parm->{$_} = $href->{$_}->{value};
        }
        # Future types to be added here

		$self->add_rule($href->{name} => $parm) || do { $err = 1 };

	}

	# Handle ordering rules
	$self->order( map { [ map { $_->{name} } @{$_->{rule}} ] } @{$parse->{order}} );

	# Handle persistent rules
	$self->persist( map { $_->{name} } @{$parse->{persist}} );

	return $err ? () : 1;
}
					
sub _parse_ling {
	my $str = shift;

	require Lingua::Phonology::RuleParser;
	my $p = Lingua::Phonology::RuleParser->new();

	my $parse = $p->Rule($str);
	return err("Couldn't parse $str") if not $parse;

	# Build the strings based on the "from" and "to" properties
	my (@do, @where);
	my $offset = 0;
	for my $i (sort keys %{$parse->{from}}) {
        # The FROM item is not '0'--test/set something
		if ($parse->{from}->{$i}) {
			my $idx = $i - $offset;
			push @where, _test_seg($idx, $parse->{from}->{$i});
			push @do, _set_seg($idx, $parse->{to}->{$i});
		}
        # The FROM item is '0'--insert a segment
		elsif (exists $parse->{from}->{$i}) {
			push @do, _insert_seg($i - $offset, $parse->{to}->{$i});
			$offset++;
		}
	}

	# Build the strings based on the "when" property
	my @cond;
	for my $cond (@{$parse->{when}}) {
		# One magnificent statement. Explanation: get the sorted, numeric keys
		# from %$cond. For each slot get a truth-value test string from it; if
		# it's more than zero, remember to decrease by offset. Join the test
		# strings with &&'s, then wrap the whole thing in ()'s.
		push @cond, 
			'('. 
				join (' && ', 
					map { _test_seg(($_ < 0) ? $_ : $_ - $offset, $cond->{$_}) } sort keys %$cond
				)
			.')'
		;
	}
	push @where, '(' . join(' || ', @cond) . ')' if @cond;

	# Final joins - return (where, do)
	return join("\n&&\n", @where), join("\n", @do);
}
	
# Segs should be an array ref, a hash ref, '__BOUNDARY', or a string
sub _test_seg {
	my ($i, $seg) = @_;
	if (ref $seg eq 'ARRAY') {
		return '(' . join(' || ', map { _test_seg($i, $_) } @$seg) . ')';
	}
	elsif (ref $seg eq 'HASH') {
        # Special case for empty hash - corresponds to "[]" in input, which we
        # want to be always true, instead of compiling to (), which would
        # always be false
		if (not keys %$seg) {
			return 1;
		}

		# General case
		return '(' . join(' && ', map { _test_feature($i, $_, $seg->{$_}) } keys %$seg) . ')';
	}
	elsif ($seg eq '__BOUNDARY') {
		return "(\$_[$i]->BOUNDARY)";
	}
	else {
		$seg = quotemeta $seg;
		return "(\$_[$i]->spell eq \"$seg\")";
	}
}

sub _set_seg {
	my ($i, $seg) = @_;
	if (ref $seg eq 'ARRAY') {
		return join ' || ', map { _set_seg($i, $_) } @$seg;
	}
	elsif (ref $seg eq 'HASH') {
		return join "\n", map { _set_feature($i, $_, $seg->{$_}) } keys %$seg;
	}
	elsif ($seg eq '__BOUNDARY') {
		return err("Can't assign a segment to be a boundary");
	}
	elsif ($seg) {
		return "Lingua::Phonology::Functions::change(\$_[$i], \"$seg\");\n";
	}
	else {
		return "\$_[$i]->clear;\n";
	}
}

# Features should be '__TRUE', '__FALSE', a number, or a string
sub _test_feature {
	my ($i, $feat, $val) = @_;
    no warnings 'numeric';

	if ($val eq '__TRUE') {
		return "(\$_[$i]->value(\"$feat\"))";
	}
	elsif ($val eq '__FALSE') {
		return "(not \$_[$i]->value(\"$feat\"))";
	}
	elsif ($val eq int $val) {
		return "(\$_[$i]->value(\"$feat\") == $val)";
	}
	else {
		return "(\$_[$i]->value(\"$feat\") eq \"$val\")";
	}
}

sub _set_feature {
	my ($i, $feat, $val) = @_;
    no warnings 'numeric';

	$val = 1 if $val eq '__TRUE';
	if ($val eq '__FALSE') {
		return "\$_[$i]->delink(\"$feat\");";
	}
	elsif ($val eq int $val) {
		return "\$_[$i]->value(\"$feat\", $val);";
	}
	else {
		return "\$_[$i]->value(\"$feat\", \"$val\");";
	}
}

sub _insert_seg {
	my ($i, $seg) = @_;
	my $rv = "my \$new$i = \$_[0]->new;\n";
    # A hack--do a normal _set_seg w/ '~' placeholder and then s/// the result
	$rv .= _set_seg('~', $seg);
	$rv =~ s/_\[~\]/new$i/g;
	
	$rv .= "\$_[$i]->INSERT_LEFT(\$new$i);\n";
	return $rv;
}

sub _to_str {
	my ($self, $file) = @_;

	require B::Deparse;
	my $dpar = B::Deparse->new('-x7', '-p', '-si6');
    $dpar->ambient_pragmas(strict => 'all', warnings => 'all');

	# Hashref structure
	my $href = { rule => {}, order => { block => [] }, persist => [] } ;

	# Construct href entries for rules
	for my $rule (keys %{$self->{RULES}}) {
        # Add our name
		for (@text) {
			$href->{rule}->{$rule}->{$_} = { value => $self->{RULES}->{$rule}->{$_} };
		}
		for (@code) {
			next if not exists $self->{RULES}->{$rule}->{$_};

            my $str = _deparse_ext $self->{RULES}->{$rule}->{$_}, $dpar or err $@;
			$href->{rule}->{$rule}->{$_} = [ $str . '    ' ]; # Extra whitespace to help alignment
		}
	}

	# Href entries for order and persist
	$href->{order}->{block} = [ map { { rule => [ map { { name => $_ } } @$_ ] } } $self->order ];
	$href->{persist} = { rule => [ map { { name => $_ } } $self->persist ] };

	return eval { _string_from_struct({ rules => $href }) };
}

sub apply {
	my ($self, $rule, $orig) = @_;

	return err("No such rule '$rule'") unless exists $self->{RULES}->{$rule};

	# Check type of input
	return err("Argument to apply() must be an array reference") unless _is($orig, 'ARRAY');
	return undef if not @$orig;
	
	# Check that we have good segments and bless into the Rules subclass
    my @rule_segs;
    for (@$orig) {
        my $add = Lingua::Phonology::Segment::Rules->new($_);
        return err "Element in array reference not a segment" if not $add;
        push @rule_segs, $add;
        $add->_RULE($self->{RULES}->{$rule});
    }
	
	# Reset the counter
	$self->{COUNT} = 0;

	# We do the following for EACH domain
	foreach (_make_domain($self->domain($rule), @rule_segs)) {
		# Readability
		my @word = @$_;

		# Make tiers, if needed
		if (my $tier = $self->tier($rule)) {
			@word = _make_tier($tier, @word);
		}

		# Create boundary segments - BEFORE filtering, since a filter might refer to boundaries
		push (@word, $BOUNDARY);
		unshift (@word, $BOUNDARY);

        # Create filters
		if (my $filter = $self->filter($rule)) {
            @word = _make_filter($filter, @word);
        }

		# Rotate to starting positions
		my $next;
		if ($self->direction($rule) eq 'leftward') {
			@word = _leftward(@word); # We need one extra rotation for leftward
			$next = \&_leftward;
		} 
		else {
			$next = \&_rightward;
		} 
		@word = $next->(@word);
			
		# Iterate over each segment for where and do
        my $where = $self->where($rule) || $property{where};
        my $do = $self->do($rule) || $property{do};
        my $result = $self->result($rule);
		while (not $word[0]->BOUNDARY) {
			if ($where->(@word)) {

				# If we're using result
				if ($result) {
					whatif {
						$do->(@word);
						die if not $result->(_cleanup(@word));
						$self->{COUNT}++;
					};
				}

                # Normal case
				else {
					# Apply the rule
					$do->(@word);
					$self->{COUNT}++;
				}
			} 

			# Rotate to the next segment
			@word = &$next(@word);
		} 
	} 

	# Clean up the word - @rule_segs retains segments in original order
	@$orig = grep { defined($_) && $_->all_values }
			 map { $_->INSERT_LEFT, shift(@$orig), $_->INSERT_RIGHT }
			 @rule_segs;
		
	return @$orig;
}

# Return only list elements that have some values set and include
# INSERT_LEFT and INSERT_RIGHT segments
sub _cleanup {
	return grep { defined($_) && $_->all_values }
           map { ($_->INSERT_LEFT, $_, $_->INSERT_RIGHT) }
           @_;
}

# A quick func to flatten hashrefs into easily comparable strings
sub _flatten {
    my ($ref, $seen) = @_;
    return '' if not defined $ref;
    $seen = {} if not $seen;
    if (ref $ref) {
        return $ref if exists $seen->{$ref};
        $seen->{$ref} = undef;
    }

    if (_is $ref, 'ARRAY' ) {
        return join '', map { _flatten($_, $seen) } @$ref;
    }
    if (_is($ref, 'HASH')) {
        return join '', map { $_, _flatten($ref->{$_}, $seen) } sort keys %$ref;
    }
    return $ref;
} 

# Make a domain
sub _make_domain ($@) {
	my $domain = shift;
	return (\@_) if not $domain;
	my @return = ();

	my $i = 0;
	while ($i < scalar(@_)) {
		my @domain = ($_[$i]);

		# Keep adding segments as long as they have the same reference for $domain
        no warnings 'uninitialized';
		while ($_[$i+1] && _flatten([$_[$i]->value_ref($domain)]) eq _flatten([$_[$i+1]->value_ref($domain)])) {
			$i++;
			push (@domain, $_[$i]);
		} #end while

		push (@return, \@domain);
		$i++;
	} 

	return @return;
}

# Make tiers
sub _make_tier ($@) {
	my $tier = shift;

	return map { Lingua::Phonology::Segment::Tier->new(@$_) }
           _make_domain $tier, grep { defined $_->value($tier) }
           @_;
}

# Make filters
sub _make_filter ($@) {
	my $filter = shift;

	my @return = ();
	for (0 .. scalar @_) {
		push (@return, $_[0]) if $filter->(@_) || $_[0]->BOUNDARY;
		@_ = _rightward(@_);
	}
	return @return;
}

# Readably do the rotations
sub _rightward {
	push(@_, shift(@_));
	return @_;
} 

sub _leftward {
	unshift(@_, pop(@_));
	return @_;
} 

# Makes rules appliable by their name
our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
	my $method = $AUTOLOAD;
	$method =~ s/.*:://;

	# For calling rules by name
	if ($self->{RULES}->{$method}) {
		# Compile functions which are rules
        no strict 'refs';
        *$method = sub {
			my ($self, $word) = @_;
			$self->apply($method, $word);
        }; 

		# Go to the rule
		return $self->$method(@_);
	} 
    die "No such method: $AUTOLOAD";
} 

sub DESTROY {
	$_[0]->clear;
}

sub apply_all {
	my ($self, $word) = @_;
	my %count = ();

	my @persist = $self->persist; # Only get this once, for speed
	for ($self->order) {
		for (@persist) {
			$self->apply($_, $word);
			$count{$_} += $self->{COUNT};
		} 
		for (@$_) {
			$self->apply($_, $word);
			$count{$_} += $self->{COUNT};
		}
	} 
	for (@persist) {
		$self->apply($_, $word);
		$count{$_} += $self->{COUNT};
	} 

	# Set COUNT to be the hashref
	$self->{COUNT} = \%count;

} 

sub order {
	my ($self, @items) = @_;
	foreach (@items) {
		$_ = [ $_ ] if not ref $_;
	}
	$self->{ORDER} = \@items if @items;
	return @{$self->{ORDER}};
} 

sub persist {
	my $self = shift;
	$self->{PERSIST} = \@_ if @_;
	return @{$self->{PERSIST}};
} 

sub count {
	return $_[0]->{COUNT};
}

1;

__END__

=head1 METHODS

=head2 new

Returns a new Lingua::Phonology::Rules object. This method accepts no 
arguments.

=head2 add_rule

Adds one or more rules to the list. Takes a series of key-value pairs, where
the keys are the names of rules to be added, and the values are hashrefs. Any of the parameters mentioned above may be used, so a single rule has the following maximal structure:

	'Name of Rule' => {
		domain => 'some_feature',
		tier => 'some_feature',
		direction => 'rightward', # Can only be 'rightward' or 'leftward'
		where => \&foo,
		do => \&bar,
		result => \&baz
	}

A detailed explanation of how to use these to make useful rules is in L<WRITING
RULES>. A typical call to add_rule might look like what follows. Assume that
'nasal' and 'SYLL' are defined in the feature set you're using, and that
nasalized() and denasalize() are subroutines defined elsewhere.

	$rules->add_rule(
		Denasalization => {
			tier => 'nasal',
			domain => 'SYLLABLE',
			direction => 'rightward',
			where => \&nasalized,
			do => \&denasalize
		}
	);

This method returns true if all rules were added successfully, otherwise false.
If a rule already exists with the name you're attempting to add, it is first
dropped.

=head2 drop_rule

    $rules->drop_rule('Rule');

Takes one argument, the name of a rule, and removes that rule. Returns the hash
reference of the properties of that rule, or undef if no such rule actually
existed.

=head2 change_rule

    $rules->change_rule(
        Denasalization => {
            tier => undef,
            where => undef,
            filter => \&nasalized
        }
    );

This method is exactly like C<add_rule()>, except that it may be used to change
parameters on an existing rule. If the method call given above were used after
the one shown for C<add_rule()>, then the 'Denasalization' rule would be
changed to have no tier or 'where' condition, but to have a filter defined by
the subroutine C<nasalized>. The other properties of the rule would be
unchanged. If you attempt to use C<change_rule()> with a rule that does not yet
exist, you will get an error.

Returns true if all changes succeed, otherwise false.

=head2 loadfile

    $rules->loadfile('phono.xml');

Loads rule definitions from a file. Returns true on success, false on failure.
This feature is new as of v0.3, and comes with new capability for reading rules
in a readable linguistic format. This is far too complex to describe here:
please consult L<Lingua::Phonology::FileFormatPOD> for details.
/
=head2 clear

    $rules->clear;

Resets the Lingua::Phonology::Rules object by deleting all rules and all
rule ordering.

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

See below.

=head2 result

All of the above methods behave identically. They may take one or two 
arguments. The first argument is the name of a rule. If only one argument
is given, then these return the property of the rule that they name. If 
two arguments are given, then they set that property to the second 
argument. For example:

	$rules->tier('Rule');				# Returns the tier
	$rules->tier('Rule', 'feature');	# Sets the tier to 'feature'
	$rules->domain('Rule');				# Returns the domain
	$rules->domain('Rule', 'feature');	# Sets the domain to 'feature'
	# Etc., etc.

=head2 apply

    $rules->apply('Denasalization', \@word);

Applies a rule to a "word". The first argument to this function is the name of
a rule, and the second argument is a reference to an array of
Lingua::Phonology:: Segment objects. apply() will take the rule named and apply
it to each segment in the array, after doing some appropriate magic with the
tiers and the domains, if specified. For a full explanation on how apply()
works and how to exploit it, see below in L<WRITING RULES>.

As of v0.2, the return value of apply() is an array with the modified contents
of the array that was passed as a reference in the call to apply(). Thus, the
return value of the rule above, if it were captured, would be the same as the
contents of C<@word> after apply() was called.

This method will set C<count>, clobbering any earlier value. See L<"count">
below.

=head2 Applying rules by name

You may also call rule names themselves as methods, in which case the only
needed argument is an array reference to the word. Thus, the following is
exactly identical to the preceding example:

	$rules->Denazalization(\@word);

=head2 apply_all

    $rules->apply_all(\@word);

When used with persist() and order(), this method can be used to apply all
rules to a word with one call. The argument to this method should be a 
list of Segment objects, just as with apply(). 

Calling apply_all() applies the rules in the order specified by order(), 
applying the rules in persist() before and after every one. Rules that are
part of the current object but which aren't specified in order() or
persist() are not applied. See L<"order"> and L<"persist"> for details on 
those methods.

For example, say you had the following code:

    $rules->persist('Persist 1', 'Persist 2');
    $rules->order(['A-1', 'A-2', 'A-3'], 'B', ['C-1', 'C-2']);
    $rules->apply_all(\@word);

When you call apply_all, the rules would be applied in this order:

    Persist 1
    Persist 2
    A-1
    A-2
    A-3
    Persist 1
    Persist 2
    B
    Persist 1
    Persist 2
    C-1
    C-2
    Persist 1
    Persist 2

In v0.2, the return value of apply_all() has changed (again). Now, apply_all()
always returns a hash reference whose keys are the names of rules and whose
values are the number of times that those rules were applied. This is the same
thing that count() returns after a call to apply_all(). See L<"count"> below.

=head2 order

    $rules->order(['A-1', 'A-2', 'A-3'], 'B', ['C-1', 'C-2']);

If called with no arguments, returns an array of the current order in 
which rules apply when calling apply_all(). If called with one or more
arguments, this sets the order in which rules apply.

The arguments to order() should be array references or strings. If you pass an
array reference, the elements in the array should be strings that are the names
of rules. A string is interpreted as an array reference of one element. When
L<"apply_all"> is called, all rules that are bundled together in one array will
be applied, then the persistent rules will be applied, as described above.

Any strings that you pass will be converted to single-element array references
when they are returned. Calling this:

    $rules->order(1, 2, 3);

actually returns this:

    ([1], [2], [3]);

=head2 persist

    $rules->persist('Persist 1', 'Persist 2');

If called with no arguments, returns an array of the current order in which
persistent rules apply when calling apply_all(). Persistent rules are applied
at the beginning and end of rule processing and between every rule in the
middle. Calling this with one or more arguments assigns the list of persistent
rules (and knocks out the existing list). You should not call persist() with
array reference arguments, unlike order().

=head2 count

After a call to apply() or apply_all(), this method can be used to find out how
many times the rule was applied. After apply(), the return value of this
function will be an integer.  After apply_all(), the return value of this
method will be a hash reference, the keys of which are the rules that were
applied, and the values of which are the times that those rules applied.
Whatever value is there will be clobbered in the next call to apply() or
apply_all(), so get it while you can.

=head1 WRITING RULES

=head2 Overview of the rule algorithm

The details of the algorithm, of course, are the module's business. But
here's a general overview of what goes on in the execution of a rule:

=over 4

=item *

The segments of the input word are broken up into domains, if a domain is
specified. This is discussed in L<"using domains">.

=item *

The segments of each domain are taken and the tier, if there is one, is applied
to it.  This generally reduces the number of segments being evaluated.  Details
of this process are discussed below in L<"using tiers">.

=item *

The segments remaining after the tier is applied are passed through the
filter. Segments for which the filter evaluates to true are passed on to
the executer.

=item *

Executing the rule involves examining every segment in turn and deciding if the
criteria for applying the rule, defined by the C<where> property, are met. If
so, the action defined by C<do> is performed.  If the direction of the rule is
specified as "rightward", then the criterion-checking and rule execution begin
with the leftmost segment and proceed to the right.  If the direction is
"leftward", the opposite occurs: focus begins on the rightmost segment and
proceeds to the left.

=item *

If a C<result> is specified, after each potential application of the C<do>
code, the result condition will be checked. If that condition is true, the rule
application goes on to the next segment. If the result condition is false, then
the rule is "undone", leaving the input word exactly the way that it was
before.

=back

The crucial point is that the rule mechanism has focus on one segment at a
time, and that this focus proceeds across each available segment in turn.
Criterion checking and execution are done for every segment. According to the
order given above, C<where> and C<do> are almost the last things to be
executed, but they're the most fundamental, so we'll examine them first.

=head2 Using 'where' and 'do'

Of course, the actual criteria and execution are done by the coderefs that
you supply. So you have to know how to write reasonable criteria and
actions.

Lingua::Phonology::Rules will pass an array of segments to both of the coderefs
that you give it. This array of segments will be arranged so that the segment
that currently has focus will be at index 0, the following segment will be at
1, and the preceding segment at -1, etc. The ends of the "word" (or domain, if
you're using domains) are indicated by special segments that have the feature
BOUNDARY, and no other features.

For example, let's say we had applied a rule to a simple four-segment word as
in the following example:

	$rules->apply('MyRule', [$b, $a, $n, $d]);

If MyRule applies rightward and there are no tiers or domains, then the
contents of @_ will be as follows on each of the four turns. Boundary
segments are indicated by '_B_':

	         $_[-2]   $_[-1]   $_[0]   $_[1]   $_[2]   $_[3]
	
	turn 1    _B_      _B_      $b      $a      $n      $d
	turn 2    _B_      $b       $a      $n      $d      _B_
	turn 3    $b       $a       $n      $d      _B_     _B_
	turn 4    $a       $n       $d      _B_     _B_     $b

This makes it easy and intuitive to refer to things like 'current segment'
and 'preceding segment'. The current segment is $_[0], the preceding one is
$_[-1], the following segment is $_[1], etc.

Yes, it's true that if the focus is on the first segment of the word, $_[-3]
refers to the last segment of the word. So be careful. Besides, you should
rarely, if ever, need to refer to something that far away. If you think you do,
then you're probably better off using a tier or filter.

Also, you should know that the boundary segments themselves are impervious to
any attempt to alter or delete them. However, there is nothing that prevents
you from setting some I<other> segment to be a boundary, which will do very
strange and probably undesirable things. Don't say I didn't warn you.

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

Note that, since the code in 'where' and 'do' simply operates on a local subset
of the segments that you provided as the word, doing something like
C<delete($_[0])> doesn't really have any effect. Yes, the local reference to
the segment at $_[0] is deleted, but the segment still exists outside of the
subroutine. Instead, write C<< $_[0]->clear >>, which removes all feature
settings from the segment. Lingua::Phonology::Rules will later clear out any
segments that have no features on them for you.

As a corollary, if you give segments that have no feature values set as
input, they will be silently dropped from the output.

=head2 Using domains

Domains change the segments that are visible to your rules by splitting the
word given into parts.

The value for a domain is the name of a feature. If the domain property is
specified for a rule, the input word given to the rule will be broken into
groups of segments whose value for that feature are references to the same
value. For the execution of the rule, those groups of segments act as
complete words with their own boundaries. For example:

	@word = $symbols->segment('b','a','r','d','a','m');

    # We make two groups of segments whose SYLLABLE features are all references
    # to the same value
    #
    # Syllable 1
	$word[0]->SYLLABLE(1);
	$word[1]->SYLLABLE($word[0]->value_ref('SYLLABLE'));
	$word[2]->SYLLABLE($word[0]->value_ref('SYLLABLE'));

	# Syllable 2
	$word[3]->SYLLABLE(1);
	$word[4]->SYLLABLE($word[3]->value_ref('SYLLABLE'));
	$word[5]->SYLLABLE($word[3]->value_ref('SYLLABLE'));

	# The preceding can be done a lot easier with the Syllable module.

	# Now we make a rule to drop the last consonant in any syllable
	$rules->add_rule(
		'Drop Final C' => {
			domain => 'SYLLABLE',
		    where => sub { $_[1]->BOUNDARY },
			do => sub { $_[0]->clear }
		}
	);
	
	$rules->apply('Drop Final C', \@word);
	# Now both the /r/ and the /m/ are marked as codas

In this example, if we hadn't specified the domain 'SYLLABLE', only the /m/
would have been marked as a coda, because only the /m/ would have been at a
boundary. With the SYLLABLE domain, however, the input word is broken up
into the two syllables, which act as their own words with respect to
boundaries.

=head2 Using tiers

Many linguistic rules behave transparently with respect to some segments or
classes of segments. Within the Rules class, this is accomplished by setting
the "tier" property of a rule.

The argument given to a tier is the name of a feature. When you specify a tier
for a rule and then apply that rule to an array of segments, the rule will only
apply to those segments that are defined for that feature. Note that I said
'defined'--binary or scalar features that are set to 0 will still appear on the
tier.

This is primarily useful for defining rules that apply across many intervening
segments. For example, let's say that you have a vowel harmony rule that
applies across any number of intervening consonants. The best solution is to
specify that the rule has the tier 'vocoid'. This will cause the rule to
completely ignore all non-vocoids: non-vocoids won't even appear in the array
that the rule works on. For example:

	# Make a rather contrived word
	@word = $symbols->segment('b','u','l','k','t','r','i'),

Note that if we were doing this without tiers, we would have to specify $_[5]
to see the final /i/ from the /u/. No such nonsense is necessary when using the
'vocoid' tier, because the only segments that the rule "sees" are ('u','i').
Thus, the following rule spreads frontness backwards (though I<why> it does so
may not be obvious to non-linguists).
	
	# Make the rule, being sure to specify the tier
	$rules->add_rule(
		VowelHarmony => {
			tier => 'vocoid',
	        direction => 'rightward',
            # We specify that the last vowel in a word should never change
			where => sub { not $_[1]->BOUNDARY },

            # All vowels before the last copy the front/backness of the vowel
            # after them (front/back position is dominated by the 'Lingual'
            # node, so we just copy the whole node).
			do => sub { $_[0]->Lingual( $_[1]->value_ref('Lingual') ) }
		}
	);
	
	# Apply the rule and print out the result
	$rules->VowelHarmony(\@word);
	print $symbols->spell(@word); # prints 'bylktri'

Tiers include one more bit of magic. When you define a tier, if consecutive
segments have references to the same value for that tier,
Lingua::Phonology::Rules will combine them into one segment.  Once such a
segment is constructed, you can assign or test values for the tier feature
itself, or any features that are children of the tier (if the tier is a node).
Assigning or testing other values will generally fail and return undef, but it
I<may> succeed if the return values of the assignment or test are the same for
every segment. Be careful.

This (hopefully) makes linguistic sense--if you're using the tier 'SYLLABLE',
what you're really interested in are interactions between whole syllables. So
that's what you see in your rule: "segments" that are really syllables and
include all of the true segments inside them.

When using domains and tiers together, the word is broken up into domains
I<before> the tier is applied. Thus, two segments which might otherwise have
been combined into a single pseudo-segment on a tier will not be combined if
they fall into different domains.

=head2 Using filters

Filters are a more flexible, but less magical, way of doing the same thing that
a tier does. You define a filter as a code reference, and all of the segments
in the input word are put through that code before going on to the rule
execution. Your code reference should accept a single
Lingua::Phonology::Segment object as an argument and return some sort of truth
value that determines whether the segment should be included.

A filter is a little like a tier and a little like a where, so here's how it
differs from both of those:

=over 4

=item *

Unlike a tier, the C<filter> property is a code reference. That means that your
test can be arbitrarily complex, and is not limited to simply testing for
whether a property is defined, which is what a tier does. On the other hand,
there is no magical combination of segments with a tier.

=item *

Also, the rule algorithm takes the filter and goes over the whole word with it
once, picking out those segments that pass through the filter. It then hands
the filtered list of segments to be evaluated by C<where> and C<do>. A C<where>
property, on the other hand, is evaluated for each segment in turn, and if the
C<where> evaluates to true, the C<do> code is immediately executed.

=back

Filters are primarily useful when you want to only see segments that meet a
certain binary or scalar feature value, or when you want to avoid the magical
segment-joining of a tier.

=head2 Using result

The C<result> parameter is currently EXPERIMENTAL, and depends on the Whatif
module, available from CPAN (but not for all architectures). You can do
interesting things with it, but it's not yet guaranteed to always do those
things.

There are many linguistic processes where it is more accurate or convenient to
stipulate a certain result, rather than certain preconditions. The C<result>
parameter accomplishes this. You provide a code reference for the C<result>
property, and after the C<do> is executed, the result is evaluated. If the
result evaluates to true, the change is considered successful and life
continues as normal. If the result evaluates to false, the change is "undone",
and the word that you're operating on reverts to its previous state. (This
undoing is devilishly hard to do by normal means. I tried to implement it
without the Whatif module and nearly went crazy.)

Some notes: The result code is only evaluated if the C<where> condition has
already been evaluated as true. It is also only evaluated in the immediate
context, with the segments in the same order as they were in the most recent
where/do. If the result fails, both the code in the C<do> and the C<result>
will be rolled back, but not the code in the C<where>.

Using a result condition imposes a mild change on the way that insertion and
deletion is handled--but see the next section for that.

=head2 Writing insertion and deletion rules

The arguments provided to the coderefs in C<where> and C<do> are in a
simple list, which means that it's not really possible to insert and delete
segments in the word from the coderef. Segments added or deleted in @_ will
disappear once the subroutine exits. Lingua::Phonology::Rules provides a
workaround for both of these cases.

Deletion can be accomplished by setting a segment to have no features set.
This is easily done with the clear() method for Segment objects. When the
coderef for C<where> or C<do> exits, any segments with no values will be
automatically deleted. A rule deleting coda consonants can be written thus:

	# Assume that we have already assigned coda consonants to have the
	# feature 'coda'
	$rules->add_rule(
		DeleteCodaC => {
			where => sub { $_[0]->coda },
	        do => sub { $_[0]->clear }
		}
	);

As a side effect of this, if you provide input segments that have no
features set, they will be silently deleted from output.

Insertion can be accomplished using the special methods INSERT_RIGHT() and
INSERT_LEFT() on a segment. The argument to INSERT_RIGHT() or INSERT_LEFT()
must be a Lingua::Phonology::Segment object, which will be added to the right
or the left of the segment on which the method is called. For example, the
following rule inserts a schwa to the left of a segment that is unsyllabified
(does not have its SYLLABLE feature set):

	$rules->add_rule(
		Epenthesize => {
			where => sub { not $_[0]->SYLLABLE },
	        do => { $_[0]->INSERT_LEFT($symbols->segment('@')) }
		}
	);

Note that the methods INSERT_RIGHT() and INSERT_LEFT() don't exist except
inside the code reference for a rule.

That the segments you insert or delete don't immediately (dis)appear.  Instead,
they wait in segmental limbo until iteration over the current word is complete,
and then are inserted/deleted all at once. Exception: when a C<result> is
specified, segment deletion/insertion occurs right before the result code is
evaluated. This is done purely to accomodate the most likely usage of
C<result>: deleting a value and then checking that resulting consonants
clusters are still valid.

=head2 Developer goodies

Theres a couple of things here that are probably of no use to the average
user, but have come in handywhen developing code for other modules or
scripts to use. And who knows, you may have a use for them.

All segments have the property C<_RULE> during the execution of a
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

The handling of insertion and deletion is very ad-hoc. Better suggestions are
welcome.

=head1 AUTHOR

Jesse S. Bangs <F<jaspax@cpan.org>>

=head1 LICENSE

This module is free software. You can distribute and/or modify it under the
same terms as Perl itself.

=cut
