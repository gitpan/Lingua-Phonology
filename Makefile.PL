#!/usr/bin/perl -w

use ExtUtils::MakeMaker qw(WriteMakefile prompt);

our $prereqs = {
    XML::Simple => 2.08,
    Parse::RecDescent => 1.9,
    B::Deparse => 0.63
};

askfor({'Whatif' => 1.0, 'Graph' => 0.2});

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
			$resp = prompt (<<EOT

It looks like you don't have the $_ module available. Though this module isn't
required to use Lingua::Phonology, if you install it you will have access to a
few extra features.  If you'd like, I can add this module to the list of
prerequisites for Lingua::Phonology, which will (probably) cause your module
installer to automatically fetch it for you.

Add $_ to list of prerequisites?
EOT
			, "yes");

			if ($resp =~ /^y/i) {
				$prereqs->{$_} = $href->{$_};
			}
		}
	}
}
