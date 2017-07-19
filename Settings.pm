package Plugins::SSAWSSQS::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Data::Dumper;


my $plugn = 'SSAWSSQS';
my $cat = 'plugin.'.uc($plugn);
my $plugt = 'PLUGIN_'.uc($plugn);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => $cat,
#	'defaultLevel' => 'WARN',
	'defaultLevel' => 'DEBUG',
	'description'  => $plugt,
});


sub name {
	return Slim::Web::HTTP::CSRF->protectName($plugt);
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/'.$plugn.'/settings/basic.html');
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	$log->info("handler");
	# referesh
	my $prefs = preferences($cat);
#	$paramsRef->{'prefs'}->{'helloname'} = $prefs->get('helloname');

        # add an empty input field for an additional aws clients


	if ( $paramRef->{'saveSettings'} ) {
		$log->info("saveSettings");
		$paramRef->{pref_awsc} = [] if (not defined $paramRef->{awsc});
		for (my $i = 0; defined $paramRef->{"pref_awsc$i"}; $i++) {
                        if (my $a = $paramRef->{"pref_awsc$i"}) {
				push @{$paramRef->{pref_awsc}}, { asid => $$a[0] , url =>$$a[1] } if ($$a[0] ne "" || $$a[1] ne "");
			}
                }
		push @{$paramRef->{pref_awsc}}, { asid => '', url => ''};
	}
	$log->debug(Dumper($client,$paramRef));
	return $class->SUPER::handler($client, $paramRef);
}

#
# awsc -> @ { asid => , url => }
#

sub prefs {
	my $prefs = preferences($cat);
	return ( $prefs,'manual_recv', 'manual_send' , 'manual_awsa', 'manual_awss', 'awsc');
}

1;

__END__
