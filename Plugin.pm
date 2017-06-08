package Plugins::SSAWSSQS::Plugin;

use base qw(Slim::Plugin::Base);

use strict;

use Slim::Utils::Strings qw (string);
use Slim::Utils::Misc;
use Slim::Utils::Prefs;
use Slim::Networking::Async;
use Amazon::SQS::Simple;
use Data::Dumper;
use Time::HiRes;

use Plugins::SSAWSSQS::Settings;

#FIXME fromSettings?
my $plugn = 'SSAWSSQS';
my $plugt = 'PLUGIN_'.$plugn;
my $cat = 'plugin.'.$plugn;

# from settings? FIXME
my $log  = Slim::Utils::Log->addLogCategory({
	'category'     => $cat,
	'defaultLevel' => 'WARN',
	'description'  => getDisplayName(),
});
#my $debug=1; # fixme from log settings?

sub getDisplayName { $plugt; }

my $sqs;
my $send;
my $recv;
my $cli;
my $prefs;

sub initPlugin {
	my $class = shift;
	$prefs = preferences($cat);
	
	# add to server setting pages
	Plugins::SSAWSSQS::Settings->new;
	#$log = $Plugins::SSAWSSQS::Settings::log;

	# Plugin setup called after other plugins setup and ready
	Slim::Utils::Timers::setTimer($class, Time::HiRes::time(), \&setup);

	# Add dispatch AWS ping command?
	$class->SUPER::initPlugin();
}

# on error... restup flag connected?
sub onConnect() {
	$log->debug("onConnect Args:" ,Dumper(@_));
	my $class = shift;
	#my $async = shift;
	#my ($class,$cli) = shift;
	$log->info("Connected");
	#$class->poster($send,$plugn." connected","Status");
	# pump first poll
	$class->poller($recv,$prefs->interval || 5);
}

sub onRead() {
	$log->debug("onRead Args:" ,Dumper(@_));
	my $async = shift; #cli..
	# passthrough
	my $class = shift;
	my $cli = shift;
	# read message from cli
	$log->debug("unpacked onRead Args:" ,Dumper($class));
	$log->debug("unpacked onRead Args:" ,Dumper($cli));
	my $msg;
	# fixme cli do we need to do any more we are just an conduit?
	my $read = sysread($async->socket,$msg,8096);
	#chomp?
	$log->info("Read $read from cli");
	$log->debug("cli: ",$msg);
	$class->poster($send,$msg);
}

sub setup {
	$log->debug("Setup Args: ",Dumper(@_));
	my $class = shift;
	# FIXME asure prefs
	# Create an SQS object
	$log->info("Using AWS Account: ",$prefs->manual_awsa);
	$log->debug("Using AWS Secret: ",substr($prefs->manual_awss,-10,10,"XXXXXXXXXX"));
	# Timeout...? FIXME
	$sqs = new Amazon::SQS::Simple($prefs->manual_awsa, $prefs->manual_awss);
	$log->info("Using AWS sendq: ",$prefs->manual_send);
	$send = $sqs->GetQueue($prefs->manual_send);
	$log->info("Using AWS recvq: ",$prefs->manual_recv);
	$recv = $sqs->GetQueue($prefs->manual_recv);
	# Purge incomming? 

	# cli connection 
	my $prefsServer = preferences('server');
	$cli = Slim::Networking::Async->new;

	# do connect 
	$cli->connect({
                        Host => '127.0.0.1', # $pref || ...
                        PeerPort =>  $prefsServer->cliport || 9090,
			onConnect => \&onConnect,
			passthrough => [$class,$cli],
			Timeout => $prefs->timeout || 30,
        });
	# submit to queue
	#$class->poster($send,"aws Test","Test");
}

sub poster () {
	my $class = shift;
	my $queue = shift;
	my $msg = shift;
	my $gid = shift;
	my $time = shift || Time::HiRes::time();
	my $count = shift|| $prefs->retrys || 3;

	if (not defined $gid) {
		$gid = "SlimServer";
	}
	$log->info("MessageGroupId => $gid, MessageDeduplicationId => $time");
	$log->debug("Message: ",$msg);
	foreach my $try (1..$count) {
		eval {
	    		$queue->SendMessage($msg,MessageGroupId => $gid,MessageDeduplicationId => ''.$time);
		};
		if ($@ && $@ !~ / Forbidden 403/) {
			#FIXME do we need to save url for this 
			$log->warn($queue," ",$@);
			next;
		} else {
		  last;
		}
	}
	#could repost later... with timer...
	#return Slim::Utils::Timers::setTimer($class, Time::HiRes::time() + $deltat, \&poller,$queue,$deltat);
}

sub poller() {
	my $class = shift;
	my $queue = shift;
	my $deltat = shift;

	# check in queue and Retrieve a message
	my $msg = $queue->ReceiveMessage(qw(AttributeName.1) => 'All');
	# Fractions/float in seconds
	#$log->debug("deltat ",$deltat);
	if (defined $msg) {
		my $body = $msg->MessageBody()."\n";
		foreach my $attr (@{$msg->{Attribute}}) {
			if ($attr->{Name} eq 'SenderId') {
				$log->info("Aws msg attr[",$attr->{Name},"]: ",$attr->{Value});
			} else {
				$log->debug("Aws msg attr[",$attr->{Name},"]: ",$attr->{Value});
			}
		}
		# dispatch to cli 
		$cli->write_async({onRead =>\&onRead,passthrough=>[$class,$cli],content_ref => \$body, Timeout=>45});
   		$queue->DeleteMessage($msg);
		# reset delta t
	}
	# FIXME back off on polls streach polls to 1's
	# search delta
	return Slim::Utils::Timers::setTimer($class, Time::HiRes::time() + $deltat, \&poller, $queue, $deltat);
}

1;

__END__
