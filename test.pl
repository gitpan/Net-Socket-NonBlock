# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test;
BEGIN { plan tests => 6 };
use Net::Socket::NonBlock;
print "module loaded..........................";
ok(1); # If we made it this far, we're ok.

#########################

# Insert your test code below, the Test module is use()ed here so read
# its man page ( perldoc Test ) for help writing this test script.

my $SockNest = Net::Socket::NonBlock->new(SilenceT => 10,)
	or die "Can not create socket nest: $@\n";

# Autoflush on
$| = 1;

#my $TestPort = 34343;
#
#print "Please enter the local port (>1024) which can be used for testing ($TestPort):";
#
#while(<STDIN>)
#	{
#	if ($_ =~ m/\A\r?\n\Z/)
#		{ last; };
#	if (($_ > 1024) && ($_ < 65536))
#		{ $TestPort = $_; last; };
#	print "Please enter the local port (>1024) which can be used for testing ($TestPort):";
#	};

my $Incoming = undef;

my $Server = $SockNest->Listen(LocalAddr => 'localhost',
                               Proto     => 'tcp',
                               Accept    => sub { $Incoming = $_[0]; return 1; },
                               Listen    => 10,)
	or die "Could not create server: $@\n";

my $Addr = 'localhost';
my $Port = $SockNest->LocalPort($Server);

print "server created.........................";
ok(2);

my $Client = $SockNest->Connect(PeerAddr => $Addr, PeerPort => $Port, Proto => 'tcp',)
	or die "Can not create client connection to \"$Addr:$Port\": $@\n";

print "client connection created..............";
ok(3);

$SockNest->IO();

if (!defined($Incoming))
	{ die "Client connection was not picked up by server\n"; };

print "client connection picked up............";
ok(4);

my $ServerStr = 'server '.time()."\r\n";
$SockNest->Puts($Incoming, $ServerStr);

my $tmpStr = '';
while (!length($tmpStr))
	{
	$SockNest->IO();
	$tmpStr = $SockNest->Gets($Client);
	if (!defined($tmpStr))
		{ die "Unexpected socket error: $@\n"; };
	};

if ($tmpStr ne $ServerStr)
	{ die sprintf("String \"%s\" expected from server but \"%s\" received\n", SafeStr($ServerStr), SafeStr($tmpStr)); };

print "data transferred from server to client.";
ok(5);

my $ClientStr = 'client '.time()."\r\n";
$SockNest->Puts($Client, $ClientStr);

$tmpStr = '';
while (!length($tmpStr))
	{
	$SockNest->IO();
	$tmpStr = $SockNest->Gets($Incoming);
	if (!defined($tmpStr))
		{ die "Unexpected socket error: $@\n"; };
	};

if ($tmpStr ne $ClientStr)
	{ die sprintf("String \"%s\" expected from server but \"%s\" received\n", SafeStr($ServerStr), SafeStr($tmpStr)); };

print "data transferred from client to server.";
ok(6);

print "All tests passed\n";
