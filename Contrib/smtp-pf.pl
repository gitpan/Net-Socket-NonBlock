#!/usr/local/bin/perl

use strict;

use UniLog       qw(:levels :options :facilities SafeStr nosyslog);
use Net::Socket::NonBlock;

# Autoflush on
$| = 1;

my $Usage = "Usage: $0 <LocalPort> <RemoteHost:RemotePort> [nodaemon] [log=<LogFile>]\n";

my %Config = ('Port'   => 1,
              'Host'   => 0,
              'Daemon' => ($^O !~ m/win32/i),
              'Debug'  => 0,
              'Log'    => undef,
             );


my $Arg = undef;
while($Arg = shift())
	{
	if    ($Arg =~ m/\Aport=(\d+)\Z/i) { $Config{'Port'}   = $1; }
	elsif ($Arg =~ m/\Ahost=(.+)\Z/i)  { $Config{'Host'}   = $1; }
	elsif ($Arg =~ m/\Anodaemon\Z/i)   { $Config{'Daemon'} = 0;  }
	elsif ($Arg =~ m/\Adebug\Z/i)      { $Config{'Debug'}  = 1;  }
	elsif ($Arg =~ m/\Alog=(.+)\Z/i)   { $Config{'Log'}    = $1; }
	else  { die $Usage; };
	};

# Configure logger
my $Logger=UniLog->new(Ident    => $0,
                       Options  => LOG_PID|LOG_CONS|LOG_NDELAY,
                       Facility => LOG_DAEMON,
                       Level    => $Config{'Debug'} ? LOG_DEBUG : LOG_INFO,
                       LogFile  => $Config{'Log'},
                       StdErr   => (!$Config{'Log'}),
                      );

my $SockNest = Net::Socket::NonBlock->new(SelectT  => 0.1, SilenceT => 0)
	or Die(1, "Error creating sockets nest: $@");

$SockNest->Listen(LocalPort => $Config{'Port'},
                  Proto     => 'tcp',
                  Accept    => \&NewConnection,
                  SilenceT  => 0,
                  Listen    => 10,)
	or Die(2, "Could not listen on port \"$Config{'Port'}\": $@");

my %ConPool = ();

print "$0 started\n";

# Daemonize process if needed
if ($Config{'Daemon'})
	{
	$SIG{PIPE} = "IGNORE";
	my $Pid=fork
		or Die(3, "Could not fork: \"$!\". Exiting.");
	($Pid == 0)
		or exit 0;
	POSIX::setsid()
		or Die(4, "Could not detach from terminal: \"$!\". Exiting.");
	$Logger->StdErr(0);
	};

my $WaitForDataAnswer = 0;
my $DataStage = 0;

while($SockNest->IO())
	{
	my $ClnSock = undef;
	my $SrvSock = undef;
	while (($ClnSock, $SrvSock) = each(%ConPool))
		{
		my $Str = undef;
		my $ClientID = $SockNest->PeerAddr($ClnSock).':'.$SockNest->PeerPort($ClnSock);
		while($Str = $SockNest->Read($ClnSock))
			{
			if ($DataStage && !$Config{'Debug'})
				{ $Logger->Message(LOG_INFO, "$ClientID length %s", length($Str)); }
			else
				{ $Logger->Message(LOG_INFO, "$ClientID from %s", SafeStr($Str)); };
			
			if    (!$DataStage && ($Str =~ m/\A\s*data(\s+.*)?\n\Z/i))
				{ $WaitForDataAnswer = 1; }
			elsif ($DataStage && ($Str =~ m/\A\.\r?\n\Z/i))
				{ $DataStage = 0; }

			$SockNest->Puts($SrvSock, $Str);
			};
		if (!defined($Str))
			{
			$Logger->Message(LOG_INFO, "$ClientID client closed");
			$SockNest->Close($ClnSock);
			$SockNest->Close($SrvSock);
			delete($ConPool{$ClnSock});
			next;
			};
		while($Str = $SockNest->Read($SrvSock))
			{
			if ($WaitForDataAnswer && ($Str =~ m/\A\s*354(\s+.*)?\n\Z/i))
				{ $DataStage = 1; };
			$WaitForDataAnswer = 0;

			$Logger->Message(LOG_INFO, "$ClientID to %s", SafeStr($Str));
			$SockNest->Puts($ClnSock, $Str);
			};
		if (!defined($Str))
			{
			$Logger->Message(LOG_INFO, "$ClientID server closed");
			$SockNest->Close($ClnSock);
			$SockNest->Close($SrvSock);
			delete($ConPool{$ClnSock});
			next;
			};
		};
	};           	

sub NewConnection
	{
	my $ClnSock = $_[0];

	my $ClientID = $SockNest->PeerAddr($ClnSock).':'.$SockNest->PeerPort($ClnSock);
	
	$ConPool{$ClnSock} = $SockNest->Connect(PeerAddr => $Config{'Host'}, Proto => 'tcp',);
	
	if (!$ConPool{$ClnSock})
		{
	        $Logger->Message(LOG_INFO, "$ClientID can not connect to $Config{'Host'}");
		delete($ConPool{$ClnSock});
		return;
		};
	$Logger->Message(LOG_INFO, "$ClientID new connection");
	return 1;
	};

sub Die
	{
	my $ExitCode = shift;
	$Logger->StdErr(1);
	$Logger->Message(LOG_ERR, shift, @_);
	exit $ExitCode;
	};

