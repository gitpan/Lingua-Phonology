#!/usr/bin/perl -w

use ExtUtils::MakeMaker;
WriteMakefile (
	NAME			=> 'Lingua::Phonology',
	VERSION_FROM 	=> 'Phonology.pm',
	PREREQ_PM		=> {
		File::Spec => 0.82,
		File::Basename => 2.6 }
);
