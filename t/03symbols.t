#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests=>21;

BEGIN {
	use_ok('Lingua::Phonology::Symbols');
}
# Comment out for debugging
no warnings 'Lingua::Phonology::Symbols';

# prepare
use Lingua::Phonology;
my $phono = new Lingua::Phonology;
my $feat = $phono->features;
$feat->loadfile;

# new as class method
ok(my $sym = Lingua::Phonology::Symbols->new($feat), 'new as class method');

# new as object method
ok(my $other = $sym->new($feat), 'new as object method');

# check features
is($sym->features, $feat, 'assignment/retreival from features()');

# prepare segments
my $b = $phono->segment;
$b->voice(1);
$b->labial(1);

# test symbol
ok($sym->symbol(b => $b), 'assign with symbol()');

# get a copy segment
ok(my $bnew = $sym->segment('b'), 'fetch copy with segment()');

# spell yourself
is($sym->spell($bnew), 'b', 'spelling via spell()');

# prototype yourself
is($sym->prototype('b'), $b, 'fetching via prototype()');

# bad symbol
my $otherphono = new Lingua::Phonology; #prepare
ok((not $sym->symbol(fail => $phono)), 'failure of symbol(): bad prototype');
ok((not $sym->symbol(fail => $otherphono->segment)), 'failure of symbol(): bad featureset');

# bad segment
ok((not $sym->segment('fail')), 'failure of segment()');

# bad spelling
ok((not $sym->spell($phono)), 'failure of spell()');

# bad prototype
ok((not $sym->prototype('fail')), 'failure of prototype()');

# change symbol
ok($sym->change_symbol(b => $bnew), 'change_symbol()');
is($sym->prototype('b'), $bnew, 'results of change_symbol()');

# bad change_symbol()
ok((not $sym->change_symbol(fail => $bnew)), 'failure of change_symbol()');

# drop symbol()
ok($sym->drop_symbol('b'), 'drop_symbol');

# loadfile (real file)
ok($sym->loadfile('test.symbols'), 'loadfile() on actual file');
ok($sym->prototype('b') && $sym->prototype('m') && $sym->prototype('p'), 'test loaded symbols');

# loadfile (defaults)
ok($sym->loadfile, 'load default symbols');

# bad load file
ok((not $sym->loadfile('nosuch.symbols')), 'failure of loadfile()');
