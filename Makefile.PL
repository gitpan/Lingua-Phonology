#!/usr/bin/perl -w

use ExtUtils::MakeMaker qw(WriteMakefile prompt);

our $prereqs = {};

askfor('Whatif', 'Graph');

WriteMakefile (
	NAME			=> 'Lingua::Phonology',
	ABSTRACT_FROM 	=> 'Phonology.pm',
	VERSION_FROM 	=> 'Phonology.pm',
	PREREQ_PM		=> $prereqs
);

sub askfor {
	for (@_) {
		if (not eval "use $_; 1") {
			$resp = prompt (<<EOT

It looks like you don't have the $_ module available. Though this module isn't
required to use Lingua::Phonology, if you install it you will have access to a
few extra features.

If you'd like, I can add this module to the list of prerequisites for
Lingua::Phonology, which will (probably) cause your module installer to
automatically fetch it for you.

Add $_ to list of prerequisites?
EOT
			, "yes");

			if ($resp =~ /^y/i) {
				$prereqs->{$_} = 0;
			}
		}
	}
}
