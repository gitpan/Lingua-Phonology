#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 23;
use Lingua::Phonology;

my $phono = new Lingua::Phonology;
$phono->loadfile;

# Load the rules file
ok $phono->rules->loadfile('t/test_rules.xml'), 'load ling rules file';
$phono->symbols->drop_symbol('j', 'w', 'H'); # Simplifies rules where we don't want to syllabify

# For debugging
$phono->savefile('test_rules_out.xml');

# Simple spell
{
    my @w1 = word('si', $phono);

    ok $phono->rules->SimpleSpell(\@w1), 'SimpleSpell applies safely';
    is $phono->symbols->spell(@w1), 'Si', 'results of SimpleSpell as expected';
}

# Simple featural
{
    my @w1 = word('by', $phono);

    ok $phono->rules->SimpleFeatural(\@w1), 'SimpleFeatural applies safely';
    is $phono->symbols->spell(@w1), 'bi', 'result of SimpleFeatural as expected';
}

# Quote values - test that strange values from the file are loaded/escaped correctly
{
    my $s1 = $phono->segment;
    $s1->aperture(q{"''});

    ok $phono->rules->QuoteValue([$s1]), 'QuoteValue applies safely';
    is $s1->aperture, q{''`%^$><" foo}, 'result of QuoteValue as expected';
}

# Featural types - test test/assignment to all types of feature
{
    my $s1 = $phono->segment;
    $s1->anterior(0);
    $s1->aperture(2);
    $s1->vocoid(1);

    ok $phono->rules->FeatureTypes([$s1]), 'FeatureTypes applies safely';
    is_deeply { $s1->all_values }, { anterior => 1, aperture => 3 }, 'result of FeatureTypes as expected';
}

# Deleting a segment
{
    my @w1 = word('bat', $phono);
    $phono->syllable->set_coda;
    $phono->syllable->syllabify(@w1);

    ok $phono->rules->Delete(\@w1), 'Delete applies safely';
    is $phono->symbols->spell(@w1), 'ba', 'result of Delete as expected';
}

# Inserting a segment
{
    my @w1 = word('ask', $phono);
    ok $phono->rules->Insert(\@w1), 'Insert applies safely';
    is $phono->symbols->spell(@w1), 'asik', 'result of Insert as expected';
}

# Segment sets
{
    my @word = word('adtagtam', $phono);
    ok $phono->rules->SegmentSet(\@word), 'SegmentSet applies safely';
    is $phono->symbols->spell(@word), 'ahtahtah', 'result of SegmentSet as expected';
}

# Condition set
{
    my @word = word('estad', $phono);
    ok $phono->rules->ConditionSet(\@word), 'ConditionSet applies safely';
    is $phono->symbols->spell(@word), 'essas', 'result of ConditionSet as expected';
}

# Multiple segs - delete
{
    my @word = word('ska', $phono);
    ok $phono->rules->MultipleDelete(\@word), 'MultipleDelete applies safely';
    is $phono->symbols->spell(@word), 'Sa', 'result of MultipleDelete as expected'
}

# Multiple Change
{
    my @word = word('big', $phono);
    ok $phono->rules->MultipleChange(\@word), 'MultipleChange applies safely';
    is $phono->symbols->spell(@word), 'pyg', 'result of MultipleChange as expected';
}

# Multiple insert
{
    my @word = word('strap', $phono);
    ok $phono->rules->MultipleInsert(\@word), 'MultipleInsert applies safely';
    is $phono->symbols->spell(@word), 'sitrap', 'result of MultipleInsert as expected';
}



sub word {
    my ($word, $phono) = @_;
    return $phono->symbols->segment(split //, $word);
}
