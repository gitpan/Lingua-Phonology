#!/usr/bin/perl

use strict;
use warnings;
use Lingua::Phonology;
use Test::More tests=>37;

# use
eval {
	use Lingua::Phonology::Functions qw/:all/;
	pass('use Lingua::Phonology::Functions'); # will pass if use is okay
};
# Comment out for debugging
no warnings 'Lingua::Phonology::Functions';

# Prepare the test materials (a lot of them)
# basic features and symbol sets
my $phono = new Lingua::Phonology;
$phono->features->loadfile;
# we'll add these features to similate being in Rules.pm, even though we're not
$phono->features->add_feature( 
	BOUNDARY => { type => 'privative' },
	INSERT_RIGHT => { type => 'scalar' },
	INSERT_LEFT => { type => 'scalar' }
);
$phono->symbols->loadfile;
# drop these symbols to avoid having to syllabify
$phono->symbols->drop_symbol('j'); 
$phono->symbols->drop_symbol('w');

# bad segments to use in failure testing
my $notseg = {};
my $bound = $phono->segment;
$bound->BOUNDARY(1);

my @word = $phono->symbols->segment(split(//, 'bkinimo'));

# assimilate
ok(assimilate('voice', $word[0], $word[1]), 'test assimilate()');
is($word[1]->value_ref('voice'), $word[0]->value_ref('voice'), 'test results of assimilate()');
ok((not assimilate('voice', $word[0], $notseg)), 'test failure of assimilate() on non-segment');
ok((not assimilate('voice', $word[0], $bound)), 'test failure of assimilate() on boundary');

# copy
ok(copy('aperture', $word[4], $word[6]), 'test copy()');
is($word[4]->aperture, $word[6]->aperture, 'test results of copy()');
ok((not copy('aperture', $word[1], $notseg)), 'test failure of copy() on non-segment');
ok((not copy('aperture', $word[1], $bound)), 'test failure of copy() on boundary');

# dissimilate
ok(dissimilate('nasal', $word[3], $word[5]), 'test dissimilate()');
ok((not $word[5]->nasal), 'test results of dissimilate()');
ok((not dissimilate('nasal', $word[3], $notseg)), 'test failure of dissimilate() on non-segment');
ok((not dissimilate('nasal', $word[3], $bound)), 'test failure of dissimilate() on boundary');

# change
ok(change($word[3], 's'), 'test change()');
is($word[3]->spell, 's', 'test result of change()');
ok((not change($notseg, 's')), 'test failure of change() on non-segment');
ok((not change($bound, 's')), 'test failure of change() on boundary');

# segment metathesize
ok(metathesize($word[0], $word[1]), 'test metathesize()');
is(($word[0]->spell . $word[1]->spell), 'gb', 'test results of metathesize()');
ok((not metathesize($word[0], $notseg)), 'test failure of metathesize() on non-segment');
ok((not metathesize($word[0], $bound)), 'test failure of metathesize() on boundary');

# feature metathesize
ok(metathesize_feature('labial', $word[4], $word[6]), 'test metathesize_feature()');
ok(($word[4]->labial) && (not $word[6]->labial), 'test results of metathesize_feature()');
ok((not metathesize_feature('labial', $word[4], $notseg)), 'test failure of metathesize_feature() on non-segment');
ok((not metathesize_feature('labial', $word[4], $bound)), 'test failure of metathesize_feature() on boundary');

# delete segments
ok(delete_seg($word[6]), 'test delete_seg()');
my %vals = $word[6]->all_values;
is(keys %vals, 0, 'test result of delete_seg()');
ok((not delete_seg($notseg)), 'test failure of delete_seg() on non-segment');
ok((not delete_seg($bound)), 'test failure of delete_seg() on boundary');

# insert before
ok(insert_before($word[1], $phono->symbols->segment('@')), 'test insert_before()');
is($word[1]->INSERT_LEFT->spell, '@', 'test result of insert_before()');
ok((not insert_before($notseg, $phono->symbols->segment('@'))), 'test failure of insert_before() on non-segment');
ok((not insert_before($bound, $phono->symbols->segment('@'))), 'test failure of insert_before() on boundary');

# insert after
ok(insert_after($word[5], $word[4]->duplicate), 'test insert_after()');
is($phono->symbols->spell($word[5]->INSERT_RIGHT), $word[4]->spell, 'test result of insert_after()');
ok((not insert_after($notseg, $word[4]->duplicate)), 'test failure of insert_after() on non-segment');
ok((not insert_after($bound, $word[4]->duplicate)), 'test failure of insert_after() on boundary');

