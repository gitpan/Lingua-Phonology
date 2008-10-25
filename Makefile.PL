#!/usr/bin/perl -w

use ExtUtils::MakeMaker qw(WriteMakefile prompt);

our $prereqs = {
    XML::Simple => 2.08,
    Parse::RecDescent => 1.9,
    B::Deparse => 0.63
};

askfor({'Whatif' => 1.0, 'Graph' => 0.5});

WriteMakefile (
	NAME			=> 'Lingua::Phonology',
	ABSTRACT_FROM 	=> 'Phonology.pm',
	VERSION_FROM 	=> 'Phonology.pm',
	PREREQ_PM		=> $prereqs
);

sub askfor {
    my $href = shift;
	for (keys %$href) {
		if (not eval "use $_; 1") {
			$resp = prompt ("Add optional module $_ as a prerequisite to be installed?", "yes");

			if ($resp =~ /^y/i) {
				$prereqs->{$_} = $href->{$_};
			}
		}
	}
}
