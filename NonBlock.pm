package Net::Socket::NonBlock;

use strict;

#$^W++;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;

@ISA = qw(Exporter);

%EXPORT_TAGS = ();

my $Key = undef;
foreach $Key (keys(%EXPORT_TAGS))
        {
        if ($Key eq 'all')
                { next; };
        push(@{$EXPORT_TAGS{'all'}}, @{$EXPORT_TAGS{$Key}});
        };

$EXPORT_TAGS{'all'}
	and @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

@EXPORT = qw(
);

$VERSION = '0.13';

use Carp;
use IO::Select;
use IO::Socket;

# Preloaded methods go here.

my $ThrowMsg = sub($$$)
	{
	my ($Nest, $CarpCond, $Msg) = @_;

	$CarpCond
		and Carp::carp $Msg;

	($Nest && $Nest->{'ErrArray'})
		and push(@{$Nest->{'ErrArray'}}, $Msg);

	return 1;
	};

sub newNest
	{ shift; return Net::Socket::NonBlock::Nest->new(@_); };
sub new
	{ shift; return Net::Socket::NonBlock::Nest->new(@_); };

my $Die = sub($)
	{ Carp::confess $_[0]; };

my $BuffSize = sub($$)
	{
	my ($SRec, $BuffName) = @_;
	($SRec->{$BuffName})
		or &{$Die}("$SRec: buffer '$BuffName' does not exists");

	my $Result = 0;
        foreach (@{$SRec->{$BuffName}})
		{
		$Result += length($_->{'Data'});
		};

	return $Result;
	};

my $BuffEmpty = sub($$)
	{
	my ($SRec, $BuffName) = @_;
	($SRec->{$BuffName})
		or &{$Die}("$SRec: buffer '$BuffName' does not exists");

	if ($SRec->{'TCP'})
		{ return (!length($SRec->{$BuffName}->[0]->{'Data'})); };

	return (!scalar(@{$SRec->{$BuffName}}));
	};

my $SockAvail = sub($)
	{
	my ($SRec) = @_;

	if (!($SRec && $SRec->{'Nest'}->{'Pool'}->{$SRec}))
		{
		$@ = "not exists";
		return;
		};

	if ($SRec->{'Close'} ||
	    ($SRec->{'EOF'} && &{$BuffEmpty}($SRec, 'Input')))
		{
		$@ = $SRec->{'Error'};
		return;
		};

	return 1;
	};

my $Close = sub($)
	{
	my ($SRec) = @_;

	$SRec->{'Nest'}->{'Select'}->remove($SRec->{'Socket'});
	$SRec->{'Socket'}->close();

	$SRec->{'Parent'}
		and $SRec->{'Parent'}->{'Clients'}--;
	
	delete($SRec->{'Nest'}->{'S2Rec'}->{$SRec->{'Socket'}});
	delete($SRec->{'Nest'}->{'Pool'}->{$SRec});
	return 1;
	};

my $EOF = sub($$)
	{
	my ($SRec, $Error) = @_;
	$SRec->{'EOF'}++;
	if (length($Error))
		{
		$SRec->{'Error'} = $Error;
		$@ = $Error;
		&{$ThrowMsg}($SRec->{'Nest'}, ($^W || $SRec->{'Nest'}->{'debug'}), "$SRec: $Error");
		};
	$SRec->{'Nest'}->{'Select'}->remove($SRec->{'Socket'});
	return;
	};

sub Gets
	{
	my ($SRec, $MaxLen) = @_;

	&{$SockAvail}($SRec)
		or return;

	$MaxLen or $MaxLen = $SRec->{'BuffSize'};

	($MaxLen < 32767)
		or $MaxLen =  32766;

	$MaxLen--;

	my @Result = ('', '', '');

	if ($SRec->{'Input'}->[0])
		{
		if (($SRec->{'Input'}->[0]->{'Data'} =~ s/\A(.{0,$MaxLen}\n)//m) ||
		    ($SRec->{'Input'}->[0]->{'Data'} =~ s/\A(.{$MaxLen}.)//m   ))
			{
			$SRec->{'PeerAddr'} = $SRec->{'Input'}->[0]->{'PeerAddr'};
			$SRec->{'PeerPort'} = $SRec->{'Input'}->[0]->{'PeerPort'};
			@Result = ($1, $SRec->{'PeerAddr'}, $SRec->{'PeerPort'});
			};

		if (!$SRec->{'TCP'} && 
		    !length($SRec->{'Input'}->[0]->{'Data'}))
			{
			shift(@{$SRec->{'Input'}});
			};
		};

	return wantarray ? @Result : $Result[0];
	};

sub Read
	{
	my ($SRec, $MaxLen) = @_;

	&{$SockAvail}($SRec)
		or return;

	$MaxLen or $MaxLen = $SRec->{'BuffSize'};

	($MaxLen < 32767)
		or $MaxLen =  32766;

	$MaxLen--;

	my @Result = ('', '', '');

	if ($SRec->{'Input'}->[0])
		{
		if (($SRec->{'Input'}->[0]->{'Data'} =~ s/\A(.{0,$MaxLen}\n)//m) ||
		    ($SRec->{'Input'}->[0]->{'Data'} =~ s/\A(.{0,$MaxLen}.)//m ))
			{
			$SRec->{'PeerAddr'} = $SRec->{'Input'}->[0]->{'PeerAddr'};
			$SRec->{'PeerPort'} = $SRec->{'Input'}->[0]->{'PeerPort'};
			@Result = ($1, $SRec->{'PeerAddr'}, $SRec->{'PeerPort'});
			};

		if (!$SRec->{'TCP'} && 
		    !length($SRec->{'Input'}->[0]->{'Data'}))
			{
			shift(@{$SRec->{'Input'}});
			};
		};

	return wantarray ? @Result : $Result[0];
	};

sub Recv
	{
	my ($SRec, $MaxLen) = @_;

	&{$SockAvail}($SRec)
		or return;

	$MaxLen or $MaxLen = $SRec->{'BuffSize'};
	
	my @Result = ('', '', '');

	if ($SRec->{'Input'}->[0])
		{
		$SRec->{'PeerAddr'} = $SRec->{'Input'}->[0]->{'PeerAddr'};
		$SRec->{'PeerPort'} = $SRec->{'Input'}->[0]->{'PeerPort'};
		@Result = (substr($SRec->{'Input'}->[0]->{'Data'}, 0, $MaxLen),
		           $SRec->{'PeerAddr'}, $SRec->{'PeerPort'});
		substr($SRec->{'Input'}->[0]->{'Data'}, 0, $MaxLen) = '';

		if (!$SRec->{'TCP'} && 
		    !length($SRec->{'Input'}->[0]->{'Data'}))
			{
			shift(@{$SRec->{'Input'}});
			};
		};

	return wantarray ? @Result : $Result[0];
	};

sub Puts
	{
	my ($SRec, $Data, $PeerAddr, $PeerPort) = @_;

	&{$SockAvail}($SRec)
		or return;

	if ($SRec->{'TCP'})
		{
		defined($SRec->{'Output'}->[0]->{'Data'})
			or $SRec->{'Output'}->[0]->{'Data'} = '';
		$SRec->{'Output'}->[0]->{'Data'} .= $Data;
		$SRec->{'Output'}->[0]->{'Dest'}  = undef;
		}
	else
		{
		defined($PeerAddr)
			or $PeerAddr = $SRec->{'PeerAddr'};
		defined($PeerPort)
			or $PeerPort = $SRec->{'PeerPort'};
	
	        my $PeerIP = inet_aton($PeerAddr);
		my $Dest = pack_sockaddr_in($PeerPort, $PeerIP);
		(defined($PeerIP) && defined($Dest))
			or  $@ = "$SRec: invalid destination address '$PeerAddr:$PeerPort'"
			and return;
		push(@{$SRec->{'Output'}}, {'Data' => $Data, 'Dest' => $Dest});
		};
	return 1;
	};

sub Send
	{ return Puts(@_); };

sub PeerAddr
	{
	my ($SRec) = @_;

	&{$SockAvail}($SRec)
		or return;
	return $SRec->{'PeerAddr'};
	};

sub PeerPort
	{
	my ($SRec) = @_;

	&{$SockAvail}($SRec)
		or return;
	
	return $SRec->{'PeerPort'};
	};

sub LocalAddr
	{
	my ($SRec) = @_;

	&{$SockAvail}($SRec)
		or return;
	
	return $SRec->{'LocalAddr'};
	};

sub LocalPort
	{
	my ($SRec) = @_;

	&{$SockAvail}($SRec)
		or return;
	
	return $SRec->{'LocalPort'};
	};

sub Handle
	{
	my ($SRec) = @_;

	&{$SockAvail}($SRec)
		or return;
	
	return $SRec->{'Socket'};
	};

sub Properties
	{
	my ($SRec, %Params) = @_;

	&{$SockAvail}($SRec)
		or return;

	my %Result = ();

	$Result{'Handle'} = $SRec->{'Socket'};

	my $Key = undef;
	foreach $Key ('Socket',    'SilenceT',  'BuffSize',  'MaxClients',
	              'ClientsST', 'Clients',   'Parent',
	              'BytesOut',  'CTime',     'ATime',     'Proto',
                      'BytesIn',   'Accept',    'PeerAddr',  'PeerPort',
                      'LocalAddr', 'LocalPort', 'Error')
                { $Result{$Key} = defined($SRec->{$Key}) ? $SRec->{$Key} : ''; };

	foreach $Key ('Input', 'Output')
		{ $Result{$Key} = &{$BuffSize}($SRec, $Key); };

	foreach $Key ('SilenceT', 'BuffSize', 'MaxClients', 'ClientsST', 'ATime', 'Accept')
		{
		(defined($Params{$Key}) && defined($SRec->{$Key}))
			and $SRec->{$Key} = $Params{$Key};
		};

	return wantarray ? %Result : \%Result;
	};

sub Close
	{
	my ($SRec, $Flush, $Timeout) = @_;

	$SRec->{'Nest'}->{'Pool'}->{$SRec}
		or return;

	$SRec->{'Close'}++;
	$SRec->{'Flush'} = (1 && $Flush);
	($Flush && $Timeout)
		and $SRec->{'CloseAt'} = time() + $Timeout;
	return;
	};

sub close
	{ Net::Socket::NonBlock::Close(@_); };
#################################################################################
#################################################################################
#################################################################################
#################################################################################

package Net::Socket::NonBlock::Nest;

use IO::Socket;
use POSIX;

sub new($%)
	{
	my ($class, %Params) = @_;

	my $Nest = {};

	$Nest->{'Select'}     = IO::Select->new()
		or return;
	$Nest->{'Pool'}       = {};
	$Nest->{'SelectT'}    = (defined($Params{'SelectT'})    ? $Params{'SelectT'}    : 0.05);
	$Nest->{'SilenceT'}   = (defined($Params{'SilenceT'})   ? $Params{'SilenceT'}   : 0);
        $Nest->{'BuffSize'}   = (defined($Params{'BuffSize'})   ? $Params{'BuffSize'}   : POSIX::BUFSIZ);
        $Nest->{'MaxClients'} = (defined($Params{'MaxClients'}) ? $Params{'MaxClients'} : 9999999999);
        $Nest->{'debug'}      = (defined($Params{'debug'})      ? $Params{'debug'}      : 0);
        $Nest->{'class'}      = $class;
	return bless $Nest => $class;
	};

sub newNest
	{ shift; return Net::Socket::NonBlock::Nest->new(@_); };

sub Properties
	{
	if (!(scalar(@_) & 1) &&
	    ($_[1] =~ m/\ANet\:\:Socket\:\:NonBlock\=HASH\(\w+\)\Z/ois))
		{
		my $Nest = shift;
		my $SRec = shift;
		$SRec = $Nest->{'Pool'}->{$SRec}
			or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
			and return;
		return wantarray ? %{scalar($SRec->Properties(@_))} :
		                     scalar($SRec->Properties(@_));
		};
	
	my ($Nest, %Params) = @_;

	my %Result = ();

	my $Key = undef;
	foreach $Key ('SelectT', 'SilenceT', 'BuffSize', 'debug')
		{ $Result{$Key} = defined($Nest->{$Key}) ? $Nest->{$Key} : ''; };

	$Result{'Sockets'} = $Nest->{'Select'}->count();

	foreach $Key ('SelectT', 'SilenceT', 'BuffSize', 'debug')
		{
		defined($Params{$Key})
			and $Nest->{$Key} = $Params{$Key};
		};

	return wantarray ? %Result : \%Result;
	};

sub NestProperties
	{ return wantarray ? %{scalar(Properties(@_))} : scalar(Properties(@_)); };

my $Cleanup = sub($$)
	{
	my ($Nest, $SRec) = @_;

	($SRec->{'Socket'} && $Nest->{'Pool'}->{$SRec})
		or  &{$Die}("$SRec: bad socket");

	my $CurTime = time();

	if ($SRec->{'Close'})
		{
		if    (!$SRec->{'Flush'})
			{
			&{$ThrowMsg}($Nest, $Nest->{'debug'}, $SRec->{'Proto'}." socket $SRec closed by request");
			&{$Close}($SRec);
			return;
			}
		elsif (&{$BuffEmpty}($SRec, 'Output'))
			{
			&{$ThrowMsg}($Nest, $Nest->{'debug'}, $SRec->{'Proto'}." socket $SRec closed after flush");
			&{$Close}($SRec);
			return;
			}
		elsif ($SRec->{'CloseAt'} && ($SRec->{'CloseAt'} < $CurTime))
			{
			&{$ThrowMsg}($Nest, $Nest->{'debug'}, $SRec->{'Proto'}." socket $SRec closed by flush timeout");
			&{$Close}($SRec);
			return;
			};
		}
	elsif ($SRec->{'SilenceT'} &&
	       ($SRec->{'SilenceT'} < ($CurTime - $SRec->{'ATime'})) &&
	       &{$BuffEmpty}($SRec, 'Input') && 
	       &{$BuffEmpty}($SRec, 'Output'))
		{
		&{$EOF}($SRec, "silence timeout occurred");
		return;
		};
	return sprintf("$SRec: %d in, %d out", &{$BuffSize}($SRec, 'Input'), &{$BuffSize}($SRec, 'Output'));
	};

my $NonBlock = sub($)
	{
	if ( $^O !~ m/win32/i)
		{
		my $Flags = fcntl($_[0], F_GETFL(), 0)
			or &{$Die}("Can not get flags for socket: $!");
		fcntl($_[0], F_SETFL(), $Flags | O_NONBLOCK())
			or &{$Die}("Can not make socket non-blocking: $!");
		};
	return $_[0];
	};

my $UpdatePeer = sub($$)
	{
	my ($SRec, $Sock) = @_;
	my $PeerName = $Sock->peername;
	if (defined($PeerName))
	        {
		($SRec->{'PeerPort'}, $SRec->{'PeerAddr'}) = unpack_sockaddr_in($PeerName);
		$SRec->{'PeerAddr'} = inet_ntoa($SRec->{'PeerAddr'});
	        }
	else
		{
	        $SRec->{'PeerAddr'} = '';
	        $SRec->{'PeerPort'} = '';
		};
        return;
	};

my $NewSRec = sub($$$%)
	{
	my ($Nest, $Socket, $CTime, $Params) = @_;

	$Params->{'Proto'} =~ m/\A\s*(.*)\s*\Z/;
	$Params->{'Proto'} = "\U$1";
	my $SRec = {'Nest'       => $Nest,
	            'Socket'     => $Socket,
		    'SilenceT'   => (defined($Params->{'SilenceT'})   ? $Params->{'SilenceT'}   : $Nest->{'SilenceT'}),
                    'BuffSize'   => (defined($Params->{'BuffSize'})   ? $Params->{'BuffSize'}   : $Nest->{'BuffSize'}),
                    'MaxClients' => (defined($Params->{'MaxClients'}) ? $Params->{'MaxClients'} : $Nest->{'MaxClients'}),
                    'ClientsST'  => (defined($Params->{'ClientsST'})  ? $Params->{'ClientsST'}  : $Nest->{'SilenceT'}),
                    'Clients'    => 0,
	            'Parent'     => '',
	            'BytesIn'    => 0,
	            'BytesOut'   => 0,
	            'CTime'      => $CTime,
	            'ATime'      => $CTime,
	            'Proto'      => $Params->{'Proto'},
	            'TCP'        => ($Params->{'Proto'} eq 'TCP'),
	            'Accept'     => $Params->{'Accept'},
	            'PeerAddr'   => '',
	            'PeerPort'   => '',
	            'LocalAddr'  => '',
	            'LocalPort'  => '',
	            'Input'      => [],
	            'Output'     => [],
	            'Close'      => 0,
	            'Flush'      => 0,
	            'CloseAt'    => 0,
	            'Error'      => '',
	           };

	&{$UpdatePeer}($SRec, $Socket);

	my $SockName = $Socket->sockname;
	if (defined($SockName))
		{
		($SRec->{'LocalPort'}, $SRec->{'LocalAddr'}) = unpack_sockaddr_in($SockName);
		$SRec->{'LocalAddr'} = inet_ntoa($SRec->{'LocalAddr'});
		};

	if ($SRec->{'TCP'})
		{
		$SRec->{'Output'}->[0]->{'Data'} = '';
		$SRec->{'Input'}->[0]->{'Data'}  = '';
		$SRec->{'Input'}->[0]->{'PeerAddr'} = $SRec->{'PeerAddr'};
		$SRec->{'Input'}->[0]->{'PeerPort'} = $SRec->{'PeerPort'};
		};

	#return wantarray ? %{$SRec} : $SRec;
	return bless $SRec => 'Net::Socket::NonBlock';
	};

my $AddSock = sub
	{
	my ($Nest, $newSock, $Params) = @_;

	$newSock or return;

	my $newSRec = &{$NewSRec}($Nest, $newSock, time(), $Params);
	
	($Nest->{'Pool'}->{$newSRec} || $Nest->{'S2Rec'}->{$newSock})
		and &{$Die}("Socket '$newSRec' already in use");

	$Nest->{'Select'}->add(&{$NonBlock}($newSock))
	        or $newSock->close()
		and $@ = "Can not add socket to select: $@"
		and return;
	
	$Nest->{'Pool'}->{$newSRec} = $newSRec;

	$Nest->{'S2Rec'}->{$newSock}  = $newSRec;

	return $newSRec;
	};

my $Accept = sub($)
	{
	my ($PRec) = @_;

	($PRec->{'Socket'} && $PRec->{'Nest'}->{'Pool'}->{$PRec})
		or  &{$Die}("$PRec: bad socket");

	if (!($PRec->{'Clients'} < $PRec->{'MaxClients'}))
		{
		$@ = "maximum number of clients exceeded";
		return;
		};

	my $newSRec = &{$AddSock}($PRec->{'Nest'}, scalar($PRec->{'Socket'}->accept()), $PRec)
		or return;

	$PRec->{'Clients'}++;
	$PRec->{'Nest'}->{'Pool'}->{$newSRec} = $newSRec;
	$PRec->{'Nest'}->{'S2Rec'}->{$newSRec->{'Socket'}} = $newSRec;
	$newSRec->{'Accept'}   = undef;
	$newSRec->{'SilenceT'} = $PRec->{'ClientsST'};
	$newSRec->{'Parent'}   = $PRec;

	if(!&{$PRec->{'Accept'}}($newSRec))
		{
		$newSRec->{'Close'}++;
		$@ = "external accept function returned a FALSE value";
		return;
		};

	return $newSRec;
	};

my $Recv = sub($$)
	{
	my ($SRec, $ATime) = @_;

	($SRec->{'Socket'} && $SRec->{'Nest'}->{'Pool'}->{$SRec})
		or  &{$Die}("$SRec: bad socket");

	my $Buf = '';
	my $Res = $SRec->{'Socket'}->recv($Buf, $SRec->{'BuffSize'}, 0);
	
	if (!defined($Res))
		{
		&{$EOF}($SRec, 'recv() fatal error');
		return;
		}
	
	if ($SRec->{'TCP'} && !length($Buf))
		{
		&{$EOF}($SRec, 'EOF');
		return;
		};

	$SRec->{'ATime'}    = time();
	$SRec->{'BytesIn'} += length($Buf);

	if ($SRec->{'TCP'})
		{
		$SRec->{'Input'}->[0]->{'Data'} .= $Buf;
		}
	else
		{
		my $tmpHash = {'Data' => $Buf};
		&{$UpdatePeer}($tmpHash, $SRec->{'Socket'});
		push(@{$SRec->{'Input'}}, $tmpHash);
		};

	return length($Buf);
	};

sub IO($$)
	{
	my ($Nest, $ErrArray) = @_;

	$ErrArray and @{$ErrArray} = ();

	$Nest->{'ErrArray'} = $ErrArray;

	my $CurTime = time();

	my $SRec = undef;

	foreach $SRec (values(%{$Nest->{'Pool'}}))
		{ &{$Cleanup}($Nest, $SRec); };

	my $Socket = undef;

	my @SockArray = ();

	my $Continue = 1;
	while ($Continue)
		{
		$Continue = 0;

		@SockArray = $Nest->{'Select'}->can_read($Nest->{'SelectT'});
		foreach $Socket (@SockArray)
			{
			$SRec  = $Nest->{'S2Rec'}->{$Socket};
	
			if ($SRec->{'EOF'} || $SRec->{'Close'} ||
			    (&{$BuffSize}($SRec, 'Input') >= $SRec->{'BuffSize'}))
				{ next; };
		
			if ($SRec->{'Accept'} && $SRec->{'TCP'})
				{
				&{$Accept}($SRec)
					and &{$ThrowMsg}(undef, $Nest->{'debug'}, "$SRec: incoming connection accepted")
					or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: Can not accept incoming connection: $@");
				$SRec->{'ATime'} = $CurTime;
				next;
				};
		
		        #$Continue = 1;

			my ($Res) = &{$Recv}($SRec, $CurTime)
				or next;
	
			&{$ThrowMsg}(undef, $Nest->{'debug'}, "$SRec: recv $Res bytes");
			};
		};

	$Continue = 1;
	while ($Continue)
		{
		$Continue = 0;
		my $Socket = undef;

		@SockArray = $Nest->{'Select'}->can_write($Nest->{'SelectT'});
		foreach $Socket (@SockArray)
			{
			$SRec  = $Nest->{'S2Rec'}->{$Socket};

			my $OutRec  = $SRec->{'Output'}->[0];

			(defined($OutRec) && !$SRec->{'EOF'})
				or next;
			
			my $DataLen = length($OutRec->{'Data'});
			
			if (!$DataLen && $SRec->{'TCP'})
				{ next; }

			$Continue++;

			my $Res = $Socket->send($OutRec->{'Data'}, 0, $OutRec->{'Dest'});

			if (!defined($Res))
				{
				&{$EOF}($SRec, "send() fatal error");
				next;
				};

			if (!(($Res == $DataLen) || ($! == POSIX::EWOULDBLOCK)))
				{
				if ($SRec->{'TCP'})
					{
					&{$EOF}($SRec, "send() fatal error");
					next;
					};
				
				my ($DP, $DA) = unpack_sockaddr_in($OutRec->{'Dest'});
				$DA = inet_ntoa($DA);
				$SRec->{'Error'} = "$SRec: send() error: ".($DataLen - $Res)." bytes were not sent to $DA:$DP";
				&{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), $SRec->{'Error'});
				
				shift(@{$SRec->{'Output'}});
				$SRec->{'BytesOut'} += $Res;
				next;
				};

			$SRec->{'ATime'}    =  $CurTime;
			$SRec->{'BytesOut'} += $Res;
			
			if ($SRec->{'TCP'})
				{
				substr($OutRec->{'Data'}, 0, $Res) = '';
				}
			else
				{
				shift(@{$SRec->{'Output'}});
				&{$UpdatePeer}($SRec, $Socket);
				};

			&{$ThrowMsg}(undef, ($Nest->{'debug'}), "$SRec: $Res bytes sent to ".$SRec->{'PeerAddr'}.':'.$SRec->{'PeerPort'});
			};
		};
	return 1;
	};


sub SelectT
	{
	my ($Nest, $SelectT) = @_;
	my $Return = $Nest->{'SelectT'};
	$SelectT and $Nest->{'SelectT'} = $SelectT;
	return $Return;
	};

sub SilenceT
	{
	my ($Nest, $SilenceT) = @_;
	my $Return = $Nest->{'SilenceT'};
	$SilenceT and $Nest->{'SilenceT'} = $SilenceT;
	return $Return;
	};

sub Listen
	{
	my ($Nest, %Params) = @_;

	if (($Params{'Proto'} =~ m/\A\s*tcp\s*\Z/io) &&
	    (ref($Params{'Accept'}) ne 'CODE'))
		{
		$@ = "'Accept' have to be a 'CODE' reference";
		return;
		};
	
	my $newSRec = &{$AddSock}($Nest, IO::Socket::INET->new(%Params), \%Params)
		or return;

	return $newSRec;
	};

sub Connect
	{
	my ($Nest, %Params) = @_;
	
	my $newSRec = &{$AddSock}($Nest, IO::Socket::INET->new(%Params), \%Params)
		or return;

	$newSRec->{'Accept'} = undef;

	return $newSRec;
	};

sub Gets
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Gets(@_);
	};
sub Read
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Read(@_);
	};
sub Recv
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Recv(@_);
	};
sub Puts
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Puts(@_);
	};
sub Send
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Send(@_);
	};
sub PeerAddr
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->PeerAddr(@_);
	};
sub PeerPort
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->PeerPort(@_);
	};
sub LocalAddr
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->LocalAddr(@_);
	};
sub LocalPort
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->LocalPort(@_);
	};
sub Handle
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Handle(@_);
	};
sub Close
	{
	my $Nest = shift;
	my $SRec = shift;
	$Nest->{'Pool'}->{$SRec}
		or  &{$ThrowMsg}($Nest, ($^W || $Nest->{'debug'}), "$SRec: bad socket name")
		and return;
	return $Nest->{'Pool'}->{$SRec}->Close(@_);
	};

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Net::Socket::NonBlock - Perl extension for easy creation multi-socket single-thread application,
especially non-forking TCP servers

I<Version 0.13>

=head1 SYNOPSIS

  # TCP port forwarder with logging
  # Works on Win32!
  
  use strict;
  use Net::Socket::NonBlock;

  $|++;
  
  my $LocalPort   = shift
  	or die "Usage: $0 <LocalPort> <RemoteHost:RemotePort>\n";
  my $RemoteHost  = shift
  	or die "Usage: $0 <LocalPort> <RemoteHost:RemotePort>\n";
  
  my $SockNest = Net::Socket::NonBlock::Nest->new(SelectT  => 0.1,
                                                  SilenceT => 0,
                                                  debug    => $^W,
                                                  BuffSize => 10240,
                                                 )
  	or die "Error creating sockets nest: $@\n";
  
  $SockNest->Listen(LocalPort => $LocalPort,
                    Proto     => 'tcp',
                    Accept    => \&NewConnection,
                    SilenceT  => 0,
                    #ClientsST => 10,
                    Listen    => 10,)
  	or die "Could not listen on port '$LocalPort': $@\n";
  
  my %ConPool = ();

  while($SockNest->IO())
  	{
  	my $Pstr = '';
  	my $ClnSock = undef;
  	my $SrvSock = undef;
  	while (($ClnSock, $SrvSock) = each(%ConPool))
  		{
  		my $ClientID = sprintf("%15.15s:%-5.5s", $SockNest->PeerAddr($ClnSock), $SockNest->PeerPort($ClnSock));
  		my $Str = undef;
  		while(($Str = $SockNest->Read($ClnSock)) && length($Str))
  			{
  			$Pstr .= "  $ClientID From CLIENT ".SafeStr($Str)."\n";
  			$SrvSock->Puts($Str);
  			};
  		if (!defined($Str))
  			{
  			$Pstr .= "  $ClientID CLIENT closed\n"; 
  			$SockNest->Close($ClnSock); # Old-style method call
  			$SrvSock->Close();          # OO-style method call
  			delete($ConPool{$ClnSock});
  			next;
  			};
  		while(($Str = $SrvSock->Read()) && length($Str))
  			{
  			$Pstr .= "  $ClientID From SERVER ".SafeStr($Str)."\n";
  			$SockNest->Puts($ClnSock, $Str);
  			};
  		if (!defined($Str))
  			{
  			$Pstr .= "  $ClientID SERVER closed\n"; 
  			$SockNest->Close($ClnSock);
  			$SrvSock->Close();
  			delete($ConPool{$ClnSock});
  			next;
  			};
  		};
  	if (length($Pstr))
  		{ print localtime()."\n".$Pstr; };
  	};           	
  
  sub NewConnection
  	{
  	my ($ClnSock) = shift
  		or return;

  	$ConPool{$ClnSock} = $SockNest->Connect(PeerAddr => $RemoteHost, Proto => 'tcp',);
  	if(!$ConPool{$ClnSock})
  		{
  		warn "Can not connect to '$RemoteHost': $@\n";
  		$ClnSock->Close();
  		delete($ConPool{$ClnSock});
  		return;
  		};
  	return 1;
  	};

  sub SafeStr
	{
	my $Str = shift
		or return '!UNDEF!';
	$Str =~ s{ ([\x00-\x1f\xff\\]) } { sprintf("\\x%2.2X", ord($1)) }gsex;
	return $Str;
	};

=head1 DESCRIPTION

This module provides simple way to work with number of non-blocking sockets.
It hides most of routine operations with C<IO::Socket::INET>, C<IO::Select>
and provides you the asynchronous Input-Output functions.

Module was designed as a part of a multi-connection SMTP relay
for WinNT platform.

The C<Net::Socket::NonBlock> module contains two packages:
C<Net::Socket::NonBlock> and C<Net::Socket::NonBlock::Nest>.

=head1 The C<Net::Socket::NonBlock::Nest> methods

=over 4

=item C<new(%PARAMHASH);>

The C<new> method creates the C<Net::Socket::NonBlock::Nest> object and returns a handle to it.
This handle is then used to call the methods below.

The C<Net::Socket::NonBlock::Nest> object itself is the table contains socket handlers,
InOut buffers, etc.
C<Net::Socket::NonBlock::Nest> object also contain a C<IO::Select> object which is common
for all sockets generated from this nest.

To create new socket you should use C<Listen> or C<Connect> methods (see below).
Also, socket could be created automatically during TCP connection accept procedure
inside of C<Net::Socket::NonBlock::Nest::IO()> method.

The I<%PARAMHASH> could contain the following keys:

=over 8

=item C<SelectT>

C<SelectT> is the timeout for C<IO::Select-E<gt>can_read>
and C<IO::Select-E<gt>can_write> function. See L<IO::Select> for details.
Default is 0.1 second.

=item C<SilenceT>

If no data was transferred trough socket for C<SilenceT> seconds
the socket will be closed. Default is '0'. 
If C<SilenceT = 0> socket will nether been closed by timeout.

This value is the default for all sockets created by C<Listen> or C<Connect> method
if another value will not be provided in C<Listen> or C<Connect> parameters.
Also, you will be able to change this parameter for any socket in nest using
C<Properties> method (see below).

=item C<BuffSize>

The size of buffer for C<IO::Socket::INET-E<gt>recv> function (see L<IO::Socket::INET>).
Default is C<POSIX::BUFSIZ> (see C<POSIX>).

This is default for all sockets which will be created and could be overwritten by 
C<Listen>, C<Connect> or C<Properties> methods.

=item C<debug>

If true, additional debug info will be printed during program execution.

=back

=item C<newNest();>

Just a synonym for C<Net::Socket::NonBlock::Nest-E<gt>new()>

=item C<Properties([%PARAMHASH]);>

The C<Properties> method returns the hash in list context
or pointer to the hash in scalar context.
Hash itself is containing nest properties which are:

=over 8

=item C<Sockets>

The number of sockets currently active on this nest.

=item C<SelectT>

=item C<SilenceT>

=item C<BuffSize>

=item C<debug>

See C<new()> for detailed explanation.

=back

The following parameters could be changed if new value will be provided in the I<C<%PARAMHASH>>:

=over 8

=item C<SelectT>

=item C<SilenceT>

=item C<BuffSize>

=item C<debug>

=back

=item C<NestProperties();>

Just a synonym for C<Net::Socket::NonBlock::Nest::Properties()>

=item C<IO([$Errors]);>

The most important method :) This method performs actual socket input-output,
accept incoming connection, close sockets, etc.
You have to call it periodically, as frequently as possible.

I<C<$Errors>> could be a reference to the array. After the C<IO()> call this array will
conatin the messages for errors ocured during the call.
Note: C<IO()> cleans this array every time.

C<Net::Socket::NonBlock::Nest::IO()> always returns 1.

=item C<SelectT([$Timeout]);>

If I<C<$Timeout>> is not specified the C<SelectT> method returns a current value of
I<C<SelectT>>.

If I<C<$Timeout>> is specified the C<SelectT> method set the I<C<SelectT>> to the
provided value and returns a previous one.

This method is provided for hysterical raisin. Please use the C<Properties> method instead.

=item C<Listen(%PARAMHASH);>

The C<Listen> method create new socket listening on I<C<LocalAddr:LocalPort>>.

The C<Listen> take the same list of arguments as C<IO::Socket::INET-E<gt>new()>
with some additions:

=over 8

=item C<SilenceT>

Silence timeout. See C<new()> for details.

=item C<Accept>

Contains the pointer to the external accept function provided by you.

When the new connection will be detected by listening TCP socket the new
C<Net::Socket::NonBlock> object will be created.
After that the external I<C<Accept>> function
will be called with just one parameter: the new C<Net::Socket::NonBlock> object.

External I<C<Accept>> have to return I<C<true>> value otherwise new socket
will be closed and connection will be rejected.

=item C<MaxClients>

The maximum number of simultaneous incoming connections.

If current number of children of this listening socket 
is bigger than C<MaxClients> new connections are not accepted.

C<'0'> mean 'do not accept new connections'.
The default is C<'9999999999'> which is quite close to unlimited.

=item C<ClientsST>

The silence timeout for children sockets. Default is the nest C<SilenceT>.

=back

C<Listen()> method returns a C<Net::Socket::NonBlock> object.
In case of problems C<Listen()> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=item C<Connect(%PARAMHASH);>

The C<Connect()> method create new socket connected to I<C<PeerAddr:PeerPort>>.

The C<Connect()> take the same list of arguments as C<IO::Socket::INET-E<gt>new()>
with same additions as C<Listen()>.
The I<Proto> key is required.

C<Connect()> method returns a C<Net::Socket::NonBlock> object.
In case of problems C<Connect()> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=item I<Important note>

C<Listen> and C<Connect> are synchronous. So if connection establishing take a long time
- for eaxmple because of slow DNS resolving - your program will be frozen for a long time.

=back

=head1 The C<Net::Socket::NonBlock> methods

=over 4

=item new() and  newNest()

Just the synonyms for C<Net::Socket::NonBlock::Nest-E<gt>new()>

I<Note: to create new C<Net::Socket::NonBlock> object you should use
C<Net::Socket::NonBlock::Nest-E<gt>new()> or C<Net::Socket::NonBlock::Nest-E<gt>Connect()>
methods>

=item C<Gets([$MaxLength]);>

For TCP sockets the C<Gets> method returns a string received from corresponding socket.
"String" means I<C<(.*\n)>>.

If data is available for reading but I<C<"\n">> is not presented
in first I<C<$MaxLength>> bytes, the I<C<$MaxLength>> bytes will be returned.

For non-TCP sockets the C<Gets> works with blocks of data read
from socket by single  C<IO::Socket::INET-E<gt>recv> call. It is necessary to provide correct
C<PeerAddr> and C<PeerPort>. So, if I<C<"\n">> found in the block and length of string
is no more than I<C<$MaxLength>>, the string will be returned.
If no I<C<"\n">> found in the block and block length is no more than I<C<$MaxLength>>,
the whole block will be returned. If string is too long or block is too big,
I<C<$MaxLength>> bytes will be returned.

Default I<C<$MaxLength>> is socket I<C<BiffSize>>.
I<C<$MaxLength>> for C<Gets> have to be no more than C<32766>.
It will be adjusted automaticaly otherwise.

If no data available for reading, C<Gets> returns empty string.

If socket closed C<Gets> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

In list context method returns an array of 3 elements:
[0] - string as in scalar context
[1] - PeerAddr
[2] - PeerPort

Note: C<Gets> is not reading data from the socket but takes it from special buffer filled by
C<Net::Socket::NonBlock::Nest::IO()> method with data read from socket during last call.

If you did not read all the data available in buffer new data will be appended
to the end of buffer.

=item C<Recv([$MaxLength]);>

For TCP sockets the C<Recv> method returns all data available from corresponding socket
if data length is no more than I<C<$MaxLength>>. Otherwise I<C<$MaxLength>> bytes returned.

For non-TCP sockets the C<Recv> works with blocks of data read
from socket by single  C<IO::Socket::INET-E<gt>recv> call. It is necessary to provide correct
C<PeerAddr> and C<PeerPort>. So, if block length is no more than I<C<$MaxLength>>,
the whole block will be returned. If block is too big, I<C<$MaxLength>> bytes will be returned.

Default I<C<$MaxLength>> is socket I<C<BiffSize>>.

If no data available for reading, C<Recv> returns empty string.

If socket is closed C<Recv> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

In list context method returns an array of 3 elements:
[0] - string as in scalar context
[1] - PeerAddr
[2] - PeerPort

Note: C<Recv> is not reading data from the socket but takes it from special buffer filled by
C<Net::Socket::NonBlock::Nest::IO()> method.

=item C<Read([$MaxLength]);>

This method is little bit eclectic but I found it useful.

If string I<C<"\n">> is presented in the buffer this method will act as C<Gets> method.
Otherwise it will act as C<Recv>.

I<C<$MaxLength>> for C<Read> have to be no more than C<32766>.
It will be adjusted automaticaly otherwise.

If socket is closed C<Recv> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=item C<Puts($Data [, $PeerAddr, $PeerPort]);>

The C<Puts> method puts data to the corresponding socket outgoing buffer.

I<C<$PeerAddr:$PeerPort>> pair is the destination which I<C<$Data>> must be sent.
If not specified these fields will be taken from socket properties.
I<C<$PeerAddr:$PeerPort>> will be ignored on TCP sockets.

If socket is closed C<Recv> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.
Otherwise it returns 1.

Note: C<Puts> is not writing data directly to the socket but puts it to the special buffer
which will be flushed to socket by C<Net::Socket::NonBlock::Nest::IO()> method during next call.

=item C<Send();>

Just a synonym for C<Puts()>.

=item C<PeerAddr();>

For TCP sockets the C<PeerAddr> method returns the IP address which is socket connected to or
empty string for listening sockets.

For non-TCP sockets the C<PeerAddr> method returns the IP address which was used for sending 
last time or IP address which is corresponding to data read by last C<Gets> or C<Recv> call.

If socket is closed C<Recv> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=item C<PeerPort();>

For TCP sockets the C<PeerPort> method returns the IP address which is socket connected to or
empty string for listening sockets.
I<C<undef>>

For non-TCP sockets the C<PeerPort> method returns the port which was used for sending 
last time or port which is corresponding to data read by last C<Gets> or C<Recv> call.

If socket is closed C<Recv> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=item C<LocalAddr();>

The C<LocalAddr> method returns the IP address for this end of the socket connection.

If socket closed C<LocalAddr> returns I<C<undef>>.

=item C<LocalPort();>

The C<LocalPort> method returns the IP address for this end of the socket connection.

If socket is closed C<Recv> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=item C<Handle();>

The C<Handle> method returns the handle to the C<IO::Socket::INET> object
associated with C<Net::Socket::NonBlock> object or I<C<undef>> if socket closed.

=item C<Properties([%PARAMHASH]);>

The C<Properties> method returns the hash in list context or pointer to the hash in scalar context.
Hash itself is containing socket properties which are:

=over 8

=item C<Handle>

The handle to the socket associated with C<Net::Socket::NonBlock> object. Read-only.

=item C<Input>

The length of data in buffer waiting to be read by C<Gets> or C<Recv>. Read-only.

=item C<Output>

The length of data in buffer waiting for sending to the socket. Read-only.

=item C<BytesIn>

The number of bytes which was received from socket. Read-only.

=item C<BytesOut>

The number of bytes which was sent out to socket. Read-only.

=item C<CTime>

The socket creation time as was returned by C<time()>. Read-only.

=item C<ATime>

The time when socket was sending or receiving data last time. Read-only.

=item C<PeerAddr>

The value is the same as returned by C<PeerAddr> method. Read-only.

=item C<PeerPort>

The value is the same as returned by C<PeerPort> method. Read-only.

=item C<LocalAddr>

The value is the same as returned by C<LocalAddr> method. Read-only.

=item C<LocalPort>

The value is the same as returned by C<LocalPort> method. Read-only.

=item C<SilenceT>

The 'silence timeout'. After C<SilenceT> seconds of inactivity the socket
will be closed. Inactivity mean 'no data send or receive'. C<0> mean 'infinity'.

=item C<ClientsST>

Make sense for TCP listening sockets only. This is the 'silence timeout' for children 
(created by incoming connection accepting) sockets. See C<Listen> for details.

=item C<Clients>

Make sense for TCP listening sockets only. Contains the number of child sockets
active at the moment.
Read-only.

=item C<MaxClients>

Make sense for TCP listening sockets only. The maximum number of child sockets.
See C<Listen> for details.

=item C<Accept>

Make sense for TCP listening sockets only.
The pointer to the external C<Accept> function. See C<Listen> for details.

=item C<Parent>

For sockets created automaticaly by accepting incoming TCP connection this field contain
the I<C<SocketID>> of parent (listening) socket.
For other sockets C<Parent> contains empty string.
Read-only.

=item C<BuffSize>

The size of buffer for C<IO::Socket::INET-E<gt>recv> function.

=item C<Error>

The message for last error ocured on this socket during last
C<Net::Socket::NonBlock::Nest::IO()> call.
Or just an empty string if no errors.

=back

The following parameters could be changed if new value is provided in the I<C<%PARAMHASH>>:

=over 4

=item Z<>

=over 4

=item C<SilenceT>

=item C<BuffSize>

=item C<MaxClients>

=item C<ClientsST>

=item C<ATime>

=item C<Accept>

=back

I<It is useless to set C<MaxClients> or C<ClientsST> or C<Accept> 
for any sockets except TCP listening sockets>

If socket is closed C<Properties> returns an I<C<undef>> value.
I<C<$@>> will contain an error message.

=back

=item C<Close([$Flush [, $Timeout]]);>

Put the "close" request for the C<Net::Socket::NonBlock> object.
The actual removing will be done by C<Net::Socket::NonBlock::Nest::IO()> method during next call.

I<C<$Flush>> is a boolean parameter which tells C<Net::Socket::NonBlock::Nest::IO()> method to flush the output buffer
before close the socket.

I<C<$Timeout>> is an amount of seconds after that the socket will be closed
even it still have some data in the output buffer.

B<Remember: it is important to call C<Close> for all socket which have to be removed
even they become to be unavailable because of I<C<send()>> or I<C<recv()>> error
or silence timeout.>

=item C<close()>

Just a synonym for C<Close()>

=back

B<Note:>

For historical reason the methods 
C<Properties()>, C<Gets()>, C<Read()>, C<Recv()>, C<Puts()>, C<Send()>, C<PeerAddr()>,
C<PeerPort()>, C<LocalAddr()>, C<LocalPort()>, C<Handle()> and C<Close()>
could be called in form

C<$SocketNest-E<gt>I<methodName>(I<SocketID>, I<methodParams>)>

I<C<SocketID>> could be the reference to the C<Net::Socket::NonBlock> object
or this reference converted to the string.

This form could be usefull if you have the C<Net::Socket::NonBlock> object reference
only as a string, for example if you are using it as a hash key.

=head2 EXPORT

None.

=head1 AUTHOR

Daniel Podolsky, E<lt>tpaba@cpan.orgE<gt>

=head1 SEE ALSO

L<IO::Socket::INET>, L<IO::Select>.

=cut
