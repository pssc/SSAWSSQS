package Plugins::SSAWSSQS::Settings;

# SlimServer Copyright (C) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

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
	$log->debug("mark");
#	if ($params->{'saveSettings'} ) {
#		$prefs->set('helloname', " $helloname");
#	}
#	
#	$params->{'prefs'}->{'helloname'} = $prefs->get('helloname');

	return $class->SUPER::handler($client, $paramRef);
}

sub prefs {
	my $prefs = preferences($cat);
	return ( $prefs,'manual_recv', 'manual_send' , 'manual_awsa', 'manual_awss');
}

1;

__END__
