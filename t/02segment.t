#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests=>27;

# Use the module
BEGIN {
	use_ok('Lingua::Phonology::Segment');
}
no warnings 'Lingua::Phonology::Segment';

# prepare
use Lingua::Phonology::Features;
use Lingua::Phonology::Symbols;
my $feat1 = new Lingua::Phonology::Features;
$feat1->loadfile('test.features');
my $feat2 = new Lingua::Phonology::Features;
$feat2->loadfile('test.features');
my $sym = Lingua::Phonology::Symbols->new($feat1);
# $sym->loadfile;

#############################
#	BASICS                  #
#############################
# new as class method
my $seg = Lingua::Phonology::Segment->new(new Lingua::Phonology::Features);
ok(UNIVERSAL::isa($seg, 'Lingua::Phonology::Segment'), 'new as class method');

# new as object method
my $nother = $seg->new($seg->featureset);
ok(UNIVERSAL::isa($seg, 'Lingua::Phonology::Segment'), 'new as object method');

# failure on no featureset
ok((not $seg->new), 'failure on no featureset');

# failure on bad feaureset
ok((not $seg->new($sym)), 'failure on bad featureset');

# get/set featureset and symbolset
ok(UNIVERSAL::isa($seg->featureset, 'Lingua::Phonology::Features'), 'get featureset');

ok($seg->featureset($feat2) && ($seg->featureset eq $feat2), 'set featureset');

ok($seg->symbolset($sym) && ($seg->symbolset eq $sym), 'set symbols');

#############################
#   VALUE ET AL             #
#############################
# assign values and test return
# true values
$seg->binary(1); # assign via name
is($seg->value('binary'), 1, 'true value with value()');
is($seg->value_text('binary'), '+', 'true value with value_text()');
is(${$seg->value_ref('binary')}, 1, 'true value with value_ref()');

# false values
$seg->binary(0);
is($seg->value('binary'), 0, 'false value with value()');
is($seg->value_text('binary'), '-', 'false value with value_text()');
is(${$seg->value_ref('binary')}, 0, 'false value with value_ref()');

# test nodes
is(ref($seg->node), 'HASH', 'return value from node');
ok($seg->node({binary=>1}), 'assign to node');
is($seg->node->{binary}, 1, 'keys of node hashref');

# test assigning equivalent refs
my $seg2 = $seg->new($feat2);
$seg2->binary($seg->value_ref('binary'));
is($seg2->value_ref('binary'), $seg->value_ref('binary'), 'reference assignment');


#############################
#	MISCELLANEOUS           #
#############################
# basic all_values
$seg->privative(1);
my %vals = $seg->all_values;
ok(($vals{privative} eq 1 &&
	$vals{binary} eq 1 &&
	not exists($vals{scalar})),
	'all_values()');

# delinking
ok($seg->delink('privative'), 'delink()');

# all_values after delinking
%vals = $seg->all_values;
ok((not exists $vals{privative}), 'all_values() after delink()');

# normal spell (needs some preparation)
$feat1->loadfile;
$sym->loadfile;
$seg->featureset($feat1);
$seg->labial(1) && $seg->voice(1);
is($seg->spell, 'b', 'successfull spell()');

# failure of spell
ok((not $seg2->spell), 'failure of spell()');

# duplicate
my $copy = $seg->duplicate;
%vals = $seg->all_values;
for (keys %vals) {
	is($seg->$_, $copy->$_, 'proper duplication');
}

# clear
$seg->clear;
%vals = $seg->all_values;
ok((not keys %vals), 'clear()');
