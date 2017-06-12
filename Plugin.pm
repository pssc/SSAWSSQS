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

my $prefs;
my $sqs;
my $recv;
my $dispatch = {};
my $poll_lower = 0.5;
my $poll_upper = 5;
my $poll_inc = 0.25;
my @poll_progression = (0.11,0.22,0.33,0.44,0.55,0.75,1,1.25,1.5,2,2.5,3,4,5);
my $poll_index;

sub initPlugin {
	my $class = shift;
	$prefs = preferences($cat);
	
	# add to server setting pages
	Plugins::SSAWSSQS::Settings->new;
	#$log = $Plugins::SSAWSSQS::Settings::log;

	# Plugin setup called after other plugins setup and ready we need cli up
	Slim::Utils::Timers::setTimer($class, Time::HiRes::time(), \&setup);

	#Fixme add client mapping command

	$class->SUPER::initPlugin();
}

# on error... restup flag connected?
sub onConnect() {
	#passthrough => [$class,$awsa,$cli,$send],
	my $class = shift;
	my $awsa = shift;
	my $cli = shift;
	my $send = shift;
	$log->info("Connected ",$awsa," out to ",$send," via cli ",$cli->socket);
	$$dispatch{$awsa} = { AWSA => $awsa, SEND => $send, CLI => $cli };
}

sub onRead() {
	$log->debug("onRead Args:" ,Dumper(@_));
	my $cli = shift; #cli..
	# passthrough
	my $class = shift;
	my $awsa = shift;
	# read message from cli
	$log->debug("unpacked onRead Args:" ,Dumper($class));
	$log->debug("unpacked onRead Args:" ,Dumper($cli));
	my $msg;
	my $read = sysread($cli->socket,$msg,8096);
	$log->info("Read $read from cli");
	$log->debug("cli: ",$msg);

	my $dispatch_rec = $$dispatch{$awsa} || $$dispatch{$prefs->manual_awsa};
	if (defined $dispatch_rec) {
		$log->info("Dispatch for ",$awsa," to ",$dispatch_rec->{SEND});
		$class->poster($dispatch_rec->{SEND},$msg);
	} else {
		$log->warn("dispatch on cli read failed");
	}
}

sub setup {
	my $class = shift;
	# FIXME asure prefs
	# Create an SQS object
	$log->info("Using AWS Account: ",$prefs->manual_awsa);
	$log->debug("Using AWS Secret: ",substr($prefs->manual_awss,-10,10,"XXXXXXXXXX"));
	$sqs = new Amazon::SQS::Simple($prefs->manual_awsa, $prefs->manual_awss);

	$log->info("Using AWS recvq: ",$prefs->manual_recv);
	$recv = $sqs->GetQueue($prefs->manual_recv);

	$log->info("Defualt send queue client mapping and cli connection");
	$class->setup_queue_cli_setup($prefs->manual_send,$prefs->manual_awsa);

	$log->info("Addional send queues client mappings and cli connections");
	# from prefs FIXME

	$log->info("Pumping first recive queue poller");
	return $class->poller($recv);
}

sub setup_queue_cli_setup {
	my ($class,$sendq,$awsa) = @_;
	my $prefsServer = preferences('server');
	# default q and client q's
	$log->info("Using AWS Account: ",$awsa, "Mapping to ",$sendq);
	my $send = $sqs->GetQueue($sendq);
	my $cli = Slim::Networking::Async->new;
	$cli->connect({
                        Host => '127.0.0.1', # $pref || ...
                        PeerPort =>  $prefsServer->cliport || 9090,
			onConnect => \&onConnect,
			passthrough => [$class,$awsa,$cli,$send],
			Timeout => $prefs->timeout || 30,
        });
}

sub poster () {
	my $class = shift;
	my $queue = shift;
	my $msg = shift;
	my $gid = shift;
	my $time = shift || Time::HiRes::time(); # FIXME this hr enough ?
	my $count = shift|| $prefs->retrys || 3;

	if (not defined $gid) {
		$gid = "SlimServer";
	}
	$log->info("MessageGroupId => $gid, MessageDeduplicationId => $gid.$time");
	$log->debug("Message: ",$msg);
	foreach my $try (1..$count) {
		eval {
			$queue->SendMessage($msg,MessageGroupId => $gid,MessageDeduplicationId => $gid.'.'.$time);
		};
		if ($@ && $@ !~ / Forbidden 403/) {
			$log->warn("Retry ",$queue," ",$@);
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
	my $deltat = shift || $prefs->poll_upper || $poll_upper;
	$log->debug("deltat ",$deltat) if ($deltat < ($prefs->poll_upper || $poll_upper));

	# check in queue and Retrieve messages
	my @msgs = $queue->ReceiveMessageBatch(qw(AttributeName.1) => 'All');
	foreach my $msg (@msgs) {
		my $body = $msg->MessageBody()."\n";
		my $sender = '';
		foreach my $attr (@{$msg->{Attribute}}) {
			if ($attr->{Name} eq 'SenderId') {
				$sender = $attr->{Value};
				$log->info("Aws msg attr[",$attr->{Name},"]: ",$attr->{Value});
			} else {
				$log->debug("Aws msg attr[",$attr->{Name},"]: ",$attr->{Value});
			}
		}
		# dispatch to cli 
		my $dispatch_rec = $$dispatch{$sender} || $$dispatch{$prefs->manual_awsa};
		if (defined $dispatch_rec) {
			$dispatch_rec->{CLI}->write_async({onRead =>\&onRead,passthrough=>[$class,$dispatch_rec->{AWSA}],content_ref => \$body, Timeout=>45});
			$queue->DeleteMessage($msg);
			if ($#poll_progression < 0) {
				$deltat = $prefs->poll_lower || $poll_lower;
			} else {
				$poll_index = 0;
				$deltat = $poll_progression[$poll_index];
			}
		} else {
			$log->warn("CLI dispatch on queue read to cli failed for ",$sender);
		}
	}
	if ($#msgs < 0 && $deltat < $poll_upper) {
		if ($#poll_progression < 0) {
			$deltat = ($deltat < ($prefs->poll_upper || $poll_upper)) ? $deltat+($prefs->poll_inc || $poll_inc): $deltat;
		} else {
			$poll_index = $poll_index + 1;
			if ($poll_index > $#poll_progression) {
				$deltat = $poll_upper;
			} else {
				$deltat = $poll_progression[$poll_index];
			}
		}
	}
	return Slim::Utils::Timers::setTimer($class, Time::HiRes::time() + $deltat, \&poller, $queue, $deltat);
}

1;

__END__
