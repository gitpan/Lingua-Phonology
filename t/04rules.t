#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests=>50;

BEGIN {
	use_ok('Lingua::Phonology::Rules');
}
# Comment out for debugging
no warnings 'Lingua::Phonology::Rules';

# This module is difficult to test. The number of possible interactions is
# enormous, and the pieces interlock very tightly, making it difficult to
# create independent tests. Still, I'm doing the best I can 

# new as a class method
ok(my $rules = new Lingua::Phonology::Rules, 'new as a class method');

# new as an object method
ok(my $otherrules = $rules->new, 'new as an object method');

# add a sample meaningless rule
# prepare some rules and a list of methods
my $testrule = {
	tier => 'tier',
	domain => 'domain',
	direction => 'leftward',
	filter => sub {},
	where => sub {},
	do => sub {}
};
my $setrule = {
	tier => 'new tier',
	domain => 'new domain',
	direction => 'rightward',
	filter => sub {},
	where => sub {},
	do => sub {}
};
my @methods = ('tier', 'domain', 'direction', 'filter', 'where','do');

# test assigning the rule
ok($rules->add_rule(test => $testrule), 'add via add_rule');

# failure on bad directions
ok((not $rules->add_rule(fail => { direction => 'sucka' })), 'add_rule failure on bad direction');

# failure on bad filter
ok((not $rules->add_rule(fail => { filter => 'nope' })), 'add_rule failure on bad filter');

# failure on bad where
ok((not $rules->add_rule(fail => { where => 'no way' })), 'add_rule failure on bad where');

# failure on bad do
ok((not $rules->add_rule(fail => { do => 'not even' })), 'add_rule failure on bad do');

# test the various get/set methods
for (@methods) {
	# test getting
	is($rules->$_('test'), $testrule->{$_}, "test get $_");

	# test setting
	ok($rules->$_('test', $setrule->{$_}), "test set $_");

	# get after set
	is($rules->$_('test'), $setrule->{$_}, "test get $_ after set");
}

# test failure of these methods
for (@methods) {
	# just do a simple get
	ok((not $rules->$_('nonesuch')), "failure of $_");
}

# test getting rid of junk (which now needs to be done)
ok($rules->clear, 'test clear');

# Here is the hard part: writing meaningful tests for the actual application of
# rules. This part is inelegant and obtuse. Oh, well.

# prepare yourself
use Lingua::Phonology;
my $phono = new Lingua::Phonology;
$phono->features->loadfile;
$phono->symbols->loadfile;
my @word = $phono->symbols->segment('b','u','d','i','n','i');

# ordering here is to facilitate easy rule-writing, not to follow the normal
# order of paramters

# test directionality
$rules->add_rule(
	left => {
		direction => 'leftward',
		where => sub { $_[1]->Coronal },
		do => sub { $_[0]->delink('Coronal') }
	},
	right => {
		direction => 'rightward',
		where => sub { $_[1]->Coronal },
		do => sub { $_[0]->delink('Coronal') }
	}
);
# test applying the rule
# WORKING ON SAME OBJECT FIXXXXX ME
ok($rules->left(\@word), 'apply leftward coronal dissimilation');
ok($word[3]->Coronal, 'test result of rule');

# reset the word
@word = $phono->symbols->segment('b','u','d','i','n','i');
ok($rules->right(\@word), 'apply rightward coronal dissimilation');
ok((not $word[3]->Coronal), 'test result of rule');

# test for domains
# make a random domain
$phono->features->add_feature(DOM => { type => 'privative' });
$word[0]->DOM(1);
$word[1]->DOM($word[0]->value_ref('DOM'));
$word[2]->DOM($word[0]->value_ref('DOM'));

$rules->add_rule(
	dom => {
		domain => 'DOM',
		where => sub { $_[1]->BOUNDARY },
		do => sub { $_[0]->delink('voice') }
	}
);
ok($rules->apply('dom', \@word), 'apply domain-final devoicing');
ok((not $word[2]->voice), 'result of devoicing');

# test for tiers
# first join the two /i/'s for place
$word[3]->ROOT($word[5]->value_ref('ROOT'));

$rules->add_rule(
	tiers => {
		tier => 'vocoid',
		direction => 'leftward',
		where => sub { $_[-1]->labial },
		do => sub { $_[0]->labial(1) }
	}
);
ok($rules->tiers(\@word), 'apply tiered rounding harmony');
is($word[5]->labial, 1, 'result of rounding harmony');

# test for filters
$rules->add_rule(
	filters => {
		filter => sub { not $_[0]->vocoid },
		where => sub { not $_[1]->voice },
		do => sub { $_[0]->voice(1) }
	}
);
ok($rules->filters(\@word), 'apply filtered voicing');
is($word[2]->voice, 1, 'result of filtered voicing');

# where and do have been implicit in every rule so far, so we won't test them
# separately

# test failure of apply()
ok((not $rules->apply('nonesuch', \@word)), 'failure of apply()');

# test persist
# fortunately, these don't have to be real rule names (is this a bug or a feature?)
my @persist = ('one','two');
ok($rules->persist(@persist), 'test persist');
is(join('', $rules->persist), join('', @persist), 'result of assignment to persist');

# test order
my @order = ('abc','def');
ok($rules->order(@order), 'test order');
is(join('', $rules->order), join('', @order), 'result of assignment to order');

# test apply_all w/ two silly rules
$rules->add_rule(
	scramble => {
		do => sub { $_[0]->voice(not $_[0]->voice) }
	},
	unscramble => {
		do => sub { $_[0]->voice(not $_[0]->voice) }
	}
);
$rules->persist('scramble');
$rules->order('unscramble');
ok($rules->apply_all(\@word), 'test apply_all');
is($word[0]->voice, undef, 'results of apply_all');
