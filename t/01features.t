#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests=>102;

##############################
# BASIC TESTS                #
##############################

BEGIN {
	# use the module
	use_ok('Lingua::Phonology::Features');
}
no warnings 'Lingua::Phonology::Features';

# new as an class method
my $feat = new Lingua::Phonology::Features;
ok(UNIVERSAL::isa($feat, 'Lingua::Phonology::Features'), 'new() as a class method');

# new as an object method
my $nother = $feat->new;
ok(UNIVERSAL::isa($nother, 'Lingua::Phonology::Features'), 'new() as an object method');

##############################
# ADDING SIMPLE FEATURES     #
##############################
# 20 tests in this block
for ('node','privative','binary','scalar') {
	# test the call to add_feature
	ok($feat->add_feature("test_$_"=>{type=>$_}), "add simple $_");

	# test the return of feature()
	is($feat->feature("test_$_")->{type}, $_, "test feature() for $_");
	
	# test type()
	is($feat->type("test_$_"), $_, "test type() for $_");

	# test change_feature()
	ok($feat->change_feature("test_$_"=>{type=>$_}), "change_feature() for $_");

	# test drop_feature
	ok($feat->drop_feature("test_$_"), "drop_feature() for $_");
} # end if

# test failure cases for preceding functions
# 4 tests in this block
ok((not $feat->add_feature("test_nonesuch"=>{type=>'nonesuch'})), "test failure for add_feature()");

# test the return of feature()
ok((not $feat->feature("test_nonesuch")), "test failure of feature()");

# test type()
ok((not $feat->type("test_nonesuch")), "test failure of type()'");

# test change_feature()
ok((not $feat->change_feature("test_nonesuch"=>{type=>'nonesuch'})), "test failure of change_feature()");

#############################
# PARENTING                 #
#############################
# preparation--add the parent features
$feat->add_feature(parent1=>{type=>'node'}, parent2=>{type=>'node'});

# add a parent via add_feature
ok($feat->add_feature(child1=>{type=>'privative', parent=>['parent1']}), 'add parent via add_feature()');

# test the newly added parent
my ($par) = $feat->parents('child1');
is($par, 'parent1', 'check added parent');

# drop the parent
ok($feat->drop_parent('child1', 'parent1'), 'drop_parent()');

# test new parent list
ok((not $feat->parents('child1')), 'check dropped parents');

# add a parent via add_parent
ok($feat->add_parent('child1', 'parent2'), 'add parent via add_parent()');

# test new parent
($par) = $feat->parents('child1');
is($par, 'parent2', 'test added parent');

# failure cases
# parent a nonexistent feature
ok((not $feat->add_parent('child1', 'nonesuch')), 'failure on adding nonexistent parent');

# parent of a nonexistent feature
ok((not $feat->add_parent('nonesuch', 'parent1')), 'failure on adding parent to a nonexistent feature');

# parent a feature that is not a node
ok((not $feat->add_parent('parent2', 'child1')), 'failure on adding a parent that is not a node');

# get parents from nonexistent feature
ok((not $feat->parents('nonesuch')), 'failure on parents of nonexistent feature');

# drop parent from nonexistent feature
ok((not $feat->drop_parent('nonesuch', 'parent1')), 'failure on drop_parent from nonexistent feature');

##############################
# CHILDING                   #
##############################
# use the features already prepared
# add a child via change_feature (already tested)
ok($feat->change_feature(parent1=>{type=>'node',child=>['child1']}), 'add child w/ change_feature');

# check via children()
my ($kid) = $feat->children('parent1');
is($kid, 'child1', 'check added child');

# drop child
ok($feat->drop_child('parent1', 'child1'), 'drop child');

# test new child list
ok((not $feat->children('parent1')), 'check dropped child');

# add child via add_child
ok($feat->add_child('parent1', 'child1'), 'add child w/ add_child');

# check via children()
($kid) = $feat->children('parent1');
is($kid, 'child1', 'check added child');

# failure cases
# child a nonexistent feature
ok((not $feat->add_child('parent1', 'nonesuch')), 'failure on adding nonexistent child');

# child of a nonexistent feature
ok((not $feat->add_child('nonesuch', 'child1')), 'failure on adding child to nonexistent feature');

# child of a feature that is not a node
ok((not $feat->add_child('child1', 'parent2')), 'failure on adding child to feature that is not a node');

# get children from fake feature
ok((not $feat->children('nonesuch')), 'failure on children from nonexistent feature');

# drop children from fake feature
ok((not $feat->drop_child('nonesuch', 'child1')), 'failure on drop_child from nonexistent feature');

#############################
# MISCELLANEOUS             #
#############################
# all_features works
ok((my %features = $feat->all_features), 'all_features()');

# load default features
ok($feat->loadfile, 'load default features');

# load an actual file
ok($feat->loadfile('test.features'), 'load an actual file');

# test loads from file
for ('privative','binary','scalar','node') {
	is($feat->type($_), $_, "test loaded feature $_");
	my ($parent) = $feat->parents($_);
	is($parent, 'node', "test parenting of $_") if ($_ ne 'node');
}

# test failure to load
ok((not $feat->loadfile('nosuch.features')), 'failure on loadfile');

#############################
#	TEXT AND NUMBER FORMS   #
#############################
# expected values
my @vals = (0,  1,  undef, '', '-',  '+',  '*');
my %expected = (
	num => {
		privative => [undef, 1, undef, undef, 1, 1, undef],
		binary => [0, 1, undef, 0, 0, 1, undef],
		scalar => [0, 1, undef, '', '-', '+', undef]
	},
	text => {
		privative => ['*', '', '*', '*', '', '', '*'],
		binary => ['-', '+', '*', '-', '-', '+', '*'],
		scalar => [0, 1, '*', '', '-', '+', '*']
	}
);
for my $i (0 .. $#vals) {
	for ('privative', 'binary', 'scalar') {
		no warnings 'uninitialized'; # To avoid warnings w/ expected undefs
		is($feat->number_form($_, $vals[$i]), $expected{num}{$_}[$i], "num for $_ on val $vals[$i]");
		is($feat->text_form($_, $vals[$i]), $expected{text}{$_}[$i], "text for $_ on val $vals[$i]");
	}
}
