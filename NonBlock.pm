package Net::Socket::NonBlock;

use strict;

#$^W++;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

require Exporter;

@ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Net::Socket::NonBlock ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
%EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

@EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

@EXPORT = qw(&SafeStr
	
);

$VERSION = '0.02';

use IO::Socket;
use IO::Select;
use POSIX;
use Carp;

# Preloaded methods go here.

sub new($%)
	{
	my ($class, %Params) = @_;

	my $Select = IO::Select->new()
		or return;

	return bless {'Select'    => IO::Select->new(),
		      'Pool'      => {},
		      'SelectT'   => (defined($Params{'SelectT'})   ? $Params{'SelectT'}   : 0.05),
		      'SilenceT'  => (defined($Params{'SilenceT'})  ? $Params{'SilenceT'}  : 3600),
                      'BuffSize'  => (defined($Params{'BuffSize'})  ? $Params{'BuffSize'}  : POSIX::BUFSIZ),
                      'InstDeath' => (defined($Params{'InstDeath'}) ? $Params{'InstDeath'} : 0), } => $class;
	};

my $NonBlock = sub($)
	{
	if ( $^O !~ m/win32/i)
		{
		my $Flags = fcntl($_[0], F_GETFL, 0);
		if (!$Flags)
			{ croak "Can not get flags for socket: \"$!\". Exiting."; };
		if (!fcntl($_[0], F_SETFL, $Flags | O_NONBLOCK))
			{ croak "Can not make socket non-blocking: \"$!\". Exiting."; };
		};
	return $_[0];
	};

my $UpdatePeer = sub($$)
	{
	my $PeerName = $_[1]->peername;
	if (defined($PeerName))
	        {
		($_[0]->{'PeerPort'}, $_[0]->{'PeerAddr'}) = unpack_sockaddr_in($PeerName);
		$_[0]->{'PeerAddr'} = inet_ntoa($_[0]->{'PeerAddr'});
	        }
	else
		{
	        $_[0]->{'PeerAddr'} = '';
	        $_[0]->{'PeerPort'} = '';
		};
        return;
	};

my $SockName = sub($$)
	{
	my $newName = $_[0].$_[1];
	$newName =~ s/(=HASH)|(IO::Socket::INET=GLOB)/:/gio;
	return $newName;
	};

my $NewSRec = sub($$%)
	{
	my ($self, $newSock, %Params) = @_;

	my $CurTime = time();
	
	my $Proto = $Params{'Proto'};
	$Proto = "\U$Proto";
	$Proto =~ s/\A\s+//;
	$Proto =~ s/\s+\Z//;
	my $SRec = {'Socket'    => $newSock,
		    'SilenceT'  => (defined($Params{'SilenceT'})  ? $Params{'SilenceT'}  : $self->{'SilenceT'}),
                    'BuffSize'  => (defined($Params{'BuffSize'})  ? $Params{'BuffSize'}  : $self->{'BuffSize'}),
                    'InstDeath' => (defined($Params{'InstDeath'}) ? $Params{'InstDeath'} : $self->{'InstDeath'}),
	            'BytesIn'   => 0,
	            'BytesOut'  => 0,
	            'CTime'     => $CurTime,
	            'ATime'     => $CurTime,
	            'Proto'     => $Proto,
	            'TCP'       => (($Proto eq 'TCP') ? 1 : 0),
	            'Accept'    => $Params{'Accept'},
	            'PeerAddr'  => '',
	            'PeerPort'  => '',
	            'LocalAddr' => '',
	            'LocalPort' => '',
	           };

	&{$UpdatePeer}($SRec, $newSock);

	if ($SRec->{'TCP'})
		{
		$SRec->{'Output'}->[0]->{'Data'} = '';
		$SRec->{'Input'}->[0]->{'Data'}  = '';
		$SRec->{'Input'}->[0]->{'PeerAddr'} = $SRec->{'PeerAddr'};
		$SRec->{'Input'}->[0]->{'PeerPort'} = $SRec->{'PeerPort'};
		};

	my $SockName = $_[1]->sockname;
	if (defined($SockName))
		{
		($SRec->{'LocalPort'}, $SRec->{'LocalAddr'}) = unpack_sockaddr_in($SockName);
		$SRec->{'LocalAddr'} = inet_ntoa($SRec->{'LocalAddr'});
		};

	return wantarray ? %{$SRec} : $SRec;
	};

my $IsDead = sub($$)
	{
	#carp "0 = ".$_[0].", 1 = ".$_[1]."\n";
	return (!defined($_[0]->{'Pool'}->{$_[1]}) ||
	        $_[0]->{'Pool'}->{$_[1]}->{'FatalError'} ||
	        ($_[0]->{'Pool'}->{$_[1]}->{'InstDeath'} && $_[0]->{'Pool'}->{$_[1]}->{'Close'}));
	};

my $Close = sub($$)
	{
	if (!defined($_[0]->{'Pool'}->{$_[1]}))
		{ return; };
	$_[0]->{'Select'}->remove($_[0]->{'Pool'}->{$_[1]}->{'Socket'});
	close($_[0]->{'Pool'}->{$_[1]}->{'Socket'});
	delete($_[0]->{'Pool'}->{$_[1]});
	return;
	};

my $BuffSize = sub ($$$)
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	my ($self, $SName, $BufName) = @_;

	if (!defined($self->{'Pool'}->{$SName}->{$BufName}))
		{
		if ($^W) { carp "Buffer \"$BufName\" is not exists for socket \"$SName\".\n"; };
		return;
		};

	my $Result = 0;
        foreach (@{$self->{'Pool'}->{$SName}->{$BufName}})
		{
		$Result += length($_->{'Data'});
		};

	return $Result;
	};

my $BuffNotEmpty = sub ($$$)
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	if ($_[0]->{'Pool'}->{$_[1]}->{'TCP'})
		{ return length($_[0]->{'Pool'}->{$_[1]}->{$_[2]}->[0]->{'Data'}); };

	return scalar(@{$_[0]->{'Pool'}->{$_[1]}->{$_[2]}});
	};

my $Eof = sub($$)
	{
	return ($_[0]->{'Pool'}->{$_[1]}->{'EOF'} && !(&{$BuffNotEmpty}($_[0], $_[1], 'Input')));
	};

sub IO($)
	{
	my $self = $_[0];

	my $SName = undef;
	my $SRec  = undef;

	my $CurTime = time();
	while(($SName, $SRec) = each(%{$self->{'Pool'}}))
		{
		if ($SRec->{'FatalError'} && $SRec->{'Close'})
			{
			my $Msg = $SRec->{'Proto'}." socket \"$SName\" dead. Removed.\n";
			if ($^W) { carp $Msg; };
			$@ .= $Msg;
			&{$Close}($self, $SName);
			next;
			};
		if ($SRec->{'InstDeath'} && $SRec->{'Close'})
			{
			my $Msg = $SRec->{'Proto'}." socket \"$SName\" closed by request.\n";
			if ($^W) { carp $Msg; };
			$@ .= $Msg;
			&{$Close}($self, $SName);
			next;
			};
		if (&{$BuffNotEmpty}($self, $SName, 'Input') ||
		    &{$BuffNotEmpty}($self, $SName, 'Output'))
			{
			next;
			}
		if ($SRec->{'Close'})
			{
			my $Msg = $SRec->{'Proto'}." socket \"$SName\" closed by request.\n";
			if ($^W) { carp $Msg; };
			$@ .= $Msg;
			&{$Close}($self, $SName);
			next;
			}
		if ($SRec->{'SilenceT'} && (($CurTime - $SRec->{'ATime'}) > $SRec->{'SilenceT'}))
			{
			my $Msg =$SRec->{'Proto'}." socket \"$SName\" closed by silence timeout.\n";
			if ($^W) { carp $Msg; };
			$@ .= $Msg;
			&{$Close}($self, $SName);
			next;
			};
		};

	my $Continue = 1;
	while ($Continue)
		{
		$Continue = 0;
		my $Socket = undef;
		foreach $Socket ($self->{'Select'}->can_read($self->{'SelectT'}))
			{
			$SName = &{$SockName}($self, $Socket);
			$SRec  = $self->{'Pool'}->{$SName};

			if ((&{$BuffSize}($self, $SName, 'Input') > $SRec->{'BuffSize'}) ||
			    $SRec->{'EOF'}   ||
			    $SRec->{'Close'} ||
			    $SRec->{'FatalError'})
				{ next; };
	
			$Continue++;

			if (defined($SRec->{'Accept'}))
				{
				my $newSock = &{$NonBlock}($Socket->accept());
	
				if (!defined($newSock))
					{
					carp $SRec->{'Proto'}." socket \"$SName\" can not accept connection: $@.\n";
					next;
					};
	
				my $newName = &{$SockName}($self, $newSock);
	
				if (!$self->{'Select'}->add($newSock))
					{
					carp "Can not add ".$SRec->{'Proto'}." socket \"$newSock\" to select: $@.\n";
					close($newSock);
					next;
					};
	
				$self->{'Pool'}->{$newName} = &{$NewSRec}($self, $newSock, %{$SRec});
				$self->{'Pool'}->{$newName}->{'Accept'} = undef;
				
				if (!(&{$SRec->{'Accept'}}($newName)))
					{
					&{$Close}($self, $newName);
					carp $SRec->{'Proto'}." socket external accept function return a FALSE value. Connection will be rejected.\n";
					};
	
				$SRec->{'ATime'}  = $CurTime;
				next;
				};
	
			my $Buf = '';
			my $Res = $Socket->recv($Buf, $SRec->{'BuffSize'}, 0);
			
			if (!defined($Res) || ($SRec->{'TCP'} && !length($Buf)))
				{
				if ($^W) { carp "Can not read from ".$SRec->{'Proto'}." socket \"$SName\". Closing.\n"; };
				if ($SRec->{'TCP'})
					{ $SRec->{'EOF'}++; }
				else
					{ $SRec->{'FatalError'}++; };
				next;
				};
	
			if ($^W) { carp $SRec->{'Proto'}." socket \"$SName\" recv ".SafeStr($Buf)."\n"; };

			$SRec->{'ATime'}    = $CurTime;
			$SRec->{'BytesIn'} += length($Buf);
			if ($SRec->{'TCP'})
				{
				$SRec->{'Input'}->[0]->{'Data'} .= $Buf;
				}
			else
				{
				my $tmpHash = {'Data' => $Buf};
				&{$UpdatePeer}($tmpHash, $Socket);
				push(@{$SRec->{'Input'}}, $tmpHash);
				};
			};
		};

	$Continue = 1;
	while ($Continue)
		{
		$Continue = 0;
		my $Socket = undef;
		foreach $Socket ($self->{'Select'}->can_write($self->{'SelectT'}))
			{
			$SName = &{$SockName}($self, $Socket);
			$SRec  = $self->{'Pool'}->{$SName};

			my $OutRec  = $SRec->{'Output'}->[0];

			if   (!defined($OutRec) || $SRec->{'FatalError'})
				{ next; }
			
			my $DataLen = length($OutRec->{'Data'});
			
			if (!$DataLen && $SRec->{'TCP'})
				{ next; }

			$Continue++;

			my $Res = $Socket->send($OutRec->{'Data'}, 0, $OutRec->{'Dest'});

			if ($^W) { carp $SRec->{'Proto'}." socket \"$SName\" send ".SafeStr($OutRec->{'Data'})."\n"; };

			if (!defined($Res))
				{
				if ($SRec->{'TCP'})
					{
					carp "Can not write to ".$SRec->{'Proto'}." socket \"$SName\". Closing.\n";
					$SRec->{'FatalError'}++;
					}
				else
					{
					if ($^W)
						{
						my ($DP, $DA) = unpack_sockaddr_in($OutRec->{'Dest'});
						$DA = inet_ntoa($DA);
						carp $SRec->{'Proto'}." socket \"$SName\" can not send to \"$DA:$DP\".\n";
						};
					shift(@{$SRec->{'Output'}});
					&{$UpdatePeer}($SRec, $Socket);
					if (defined($SRec->{'Output'}->[0]))
						{ $Continue++; };
					};
				next;
				};

			if (($Res != $DataLen) && ($! != POSIX::EWOULDBLOCK))
				{
				if ($SRec->{'TCP'})
					{
					carp "Can not write to ".$SRec->{'Proto'}." socket \"$SName\". Closing.\n";
					$SRec->{'FatalError'}++;
					next;
					};
				carp 'Error: '.($DataLen - $Res)." bytes of $DataLen was NOT written to ".$SRec->{'Proto'}." socket \"$SName\" on last send.\n";
				};

			$SRec->{'ATime'}    =  $CurTime;
			$SRec->{'BytesOut'} += $Res;
			
			if ($SRec->{'TCP'})
				{ substr($OutRec->{'Data'}, 0, $Res) = ''; }
			else
				{
				shift(@{$SRec->{'Output'}});
				&{$UpdatePeer}($SRec, $Socket);
				};
			};
		};
	return 1;
	};

sub SelectT
	{
	my $Return = $_[0]->{'SelectT'};
	if (defined($_[1]))
		{ $_[0]->{'SelectT'} = $_[1]; };
	return $Return;
	};

sub Listen
	{
	my ($self, %Params) = @_;

	if ($Params{'Proto'} =~ m/\A\s*tcp\s*\Z/io)
		{
		my $refType = ref($Params{'Accept'});
	
		if (!$refType)
			{ $refType = 'undefined'; };

		if ($refType ne 'CODE')
			{
			$@ = "Could not use $refType reference as a reference to external Accept routine";
			return;
			};
		};
	
	my $newSock = &{$NonBlock}(IO::Socket::INET->new(%Params));

	if (!defined($newSock))
		{ return; };
	
	if (!$self->{'Select'}->add($newSock))
		{
		close($newSock);
		return;
		};

	my $SName = &{$SockName}($self, $newSock);

	$self->{'Pool'}->{$SName} = &{$NewSRec}($self, $newSock, %Params);

	return $SName;
	};

sub Connect
	{
	my ($self, %Params) = @_;
	
	my $newSock = &{$NonBlock}(IO::Socket::INET->new(%Params));

	if (!defined($newSock))
		{ return; };
	
	if (!$self->{'Select'}->add($newSock))
		{
		close($newSock);
		return;
		};

	my $SName = &{$SockName}($self, $newSock);

	$self->{'Pool'}->{$SName} = &{$NewSRec}($self, $newSock, %Params);
	$self->{'Pool'}->{$SName}->{'Accept'} = undef;

	return $SName;
	};

sub Gets
	{
	my ($self, $SName, $MaxLen) = @_;

	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	if (&{$Eof}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is closed.\n"; };
		return;
		};

	my $SRec = $self->{'Pool'}->{$SName};

	if (!defined($MaxLen))
		{ $MaxLen = $SRec->{'BuffSize'}; };
	if ($MaxLen > 32766)
		{
		if ($^W) { carp "\$MaxLen parameter too big. Adjusted to 32766.\n"; };
		$MaxLen = 32766;
		};

	$MaxLen--;

	my @Result = ($SRec->{'Close'} ? () : ('', '', ''));

	if (defined($SRec->{'Input'}->[0]))
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
	my ($self, $SName, $MaxLen) = @_;

	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	if (&{$Eof}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is closed.\n"; };
		return;
		};

	my $SRec = $self->{'Pool'}->{$SName};

	if (!defined($MaxLen))
		{ $MaxLen = $SRec->{'BuffSize'}; };
	if ($MaxLen > 32766)
		{
		if ($^W) { carp "\$MaxLen parameter too big. Adjusted to 32766.\n"; };
		$MaxLen = 32766;
		};

	$MaxLen--;

	my @Result = ($SRec->{'Close'} ? () : ('', '', ''));

	if (defined($SRec->{'Input'}->[0]))
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
	my ($self, $SName, $MaxLen) = @_;

	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	if (&{$Eof}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is closed.\n"; };
		return;
		};

	my $SRec = $self->{'Pool'}->{$SName};

	if (!defined($MaxLen))
		{ $MaxLen = $SRec->{'BuffSize'}; };
	
	my @Result = ($SRec->{'Close'} ? () : ('', '', ''));

	if (defined($SRec->{'Input'}->[0]))
		{
		my $OrigBufLen = length($SRec->{'Input'}->[0]->{'Data'});
		$SRec->{'PeerAddr'} = $SRec->{'Input'}->[0]->{'PeerAddr'};
		$SRec->{'PeerPort'} = $SRec->{'Input'}->[0]->{'PeerPort'};
		@Result = (substr($SRec->{'Input'}->[0]->{'Data'}, 0, $MaxLen),
		           $SRec->{'PeerAddr'}, $SRec->{'PeerPort'});
		substr($SRec->{'Input'}->[0]->{'Data'}, 0, $MaxLen) = '';

		if ($^W) { carp "Socket \"".$_[1].'": '.length($Result[0])." of $OrigBufLen bytes taken from input buffer by Recv.\n"; };

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
	my ($self, $SName, $Data, $PeerAddr, $PeerPort) = @_;

	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	my $SRec = $self->{'Pool'}->{$SName};

	if($SRec->{'Close'} || $SRec->{'EOF'})
		{ return 1; };

	if ($SRec->{'TCP'})
		{
		$SRec->{'Output'}->[0]->{'Data'} .= $Data;
		}
	else
		{
		defined($PeerAddr) or $PeerAddr = $SRec->{'PeerAddr'};
		defined($PeerPort) or $PeerPort = $SRec->{'PeerPort'};
	
	        my $PeerIP = inet_aton($PeerAddr);
		my $Dst = pack_sockaddr_in($PeerPort, $PeerIP);
		if (!(defined($PeerIP) && defined($Dst)))
			{
			carp "Socket \"".$_[1]."\": invalid destination address \"$PeerAddr:$PeerPort\".\n";
			return;
			};
		my $tmpHash = {'Data' => $Data,
		              };
		
		push(@{$SRec->{'Output'}}, {'Data' => $Data, 'Dest' => $Dst});
		};
	return 1;
	};

sub Send
	{ return Puts(@_); };

sub PeerAddr
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};
	return $_[0]->{'Pool'}->{$_[1]}->{'PeerAddr'};
	};

sub PeerPort
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};
	return $_[0]->{'Pool'}->{$_[1]}->{'PeerPort'};
	};

sub LocalAddr
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};
	return $_[0]->{'Pool'}->{$_[1]}->{'LocalAddr'};
	};

sub LocalPort
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};
	return $_[0]->{'Pool'}->{$_[1]}->{'LocalPort'};
	};

sub Handle
	{
	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};
	return $_[0]->{'Pool'}->{$_[1]}->{'Socket'};
	};

sub Properties
	{
	my ($self, $SName, %Params) = @_;

	if (&{$IsDead}($_[0], $_[1]))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	my %Result = ();

	my $SRec = $self->{'Pool'}->{$SName};

	$Result{'Handle'} = $SRec->{'Socket'};
	foreach ('BytesIn', 'BytesOut', 'CTime', 'ATime', 'PeerAddr', 'PeerPort', 'LocalAddr', 'LocalPort', 'SilenceT', 'BuffSize', 'Accept', 'InstDeath')
		{
		$Result{$_} = $SRec->{$_};
		};
	foreach ('Input', 'Output')
		{
		$Result{$_} = &{$BuffSize}($self, $SName, $_);
		};

	foreach ('SilenceT', 'BuffSize', 'Accept', 'InstDeath')
		{
		if (defined($Params{$_}) && defined($SRec->{$_}))
			{ $SRec->{$_} = $Params{$_}; };
		};

	return wantarray ? %Result : \%Result;
	};

sub Close
	{
	if (!defined($_[0]->{'Pool'}->{$_[1]}))
		{
		if ($^W) { carp "Socket \"".$_[1]."\" is not available.\n"; };
		return;
		};

	$_[0]->{'Pool'}->{$_[1]}->{'Close'}++;
	return;
	};

sub SafeStr($)
	{
	my $Str = shift
		or return '!UNDEF!';
	$Str =~ s{ ([\x00-\x1f\xff\\]) } { sprintf("\\x%2.2X", ord($1)) }gsex;
	return $Str;
	};

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Net::Socket::NonBlock - Perl extension for easy creation multi-socket single-thread application,
especially non-forking TCP servers

=head1 SYNOPSIS

  # TCP port forwarder with logging
  # Works on Win32!

  use Net::Socket::NonBlock;

  my $LocalPort   = shift
  	or die "Usage: $0 <LocalPort> <RemoteHost:RemotePort>\n";
  my $RemoteHost  = shift
  	or die "Usage: $0 <LocalPort> <RemoteHost:RemotePort>\n";

  my $SockNest = Net::Socket::NonBlock->new(SelectT  => 0.05,
                                            SilenceT => 60,
                                           )
  	or die "Error creating sockets nest: $@\n";

  # Autoflush on
  $| = 1;

  $SockNest->Listen(LocalPort      => $LocalPort,
                    Proto          => 'tcp',
                    Accept         => \&NewConnection,
                    SilenceT => 0,
                    Listen         => 10,)
  	or die "Could not listen on port \"$LocalPort\": $@\n";

  my %ConPool = ();

  while($SockNest->IO())
  	{
  	my $Pstr = '';
  	my $ClnSock = undef;
  	my $SrvSock = undef;
  	while (($ClnSock, $SrvSock) = each(%ConPool))
  		{
  		my $Str = undef;
  		my $ClientID = sprintf("%15.15s:%-5.5s", $SockNest->PeerAddr($ClnSock), $SockNest->PeerPort($ClnSock));
  		while(($Str = $SockNest->Read($ClnSock)) && length($Str))
  			{
  			$Pstr .= "  $ClientID CLIENT ".SafeStr($Str)."\n";
  			$SockNest->Puts($SrvSock, $Str);
  			};
  		if (!defined($Str))
  			{
  			$SockNest->Close($SrvSock);
  			delete($ConPool{$ClnSock});
  			$Pstr .= "  $ClientID CLIENT closed\n"; 
  			next;
  			};
  		while(($Str = $SockNest->Read($SrvSock)) && length($Str))
  			{
  			$Pstr .= "  $ClientID SERVER ".SafeStr($Str)."\n";
  			$SockNest->Puts($ClnSock, $Str);
  			};
  		if (!defined($Str))
  			{
  			$SockNest->Close($ClnSock);
  			delete($ConPool{$ClnSock});
  			$Pstr .= "  $ClientID SERVER closed\n"; 
  			next;
  			};
  		};
  	if (length($Pstr))
  		{ print localtime()."\n".$Pstr; };
  	};           	

  sub NewConnection
  	{
  	my $ClnSockID = $_[0];
  
  	$ConPool{$ClnSockID} = $SockNest->Connect(PeerAddr => $RemoteHost,
  	                                          Proto    => 'tcp',);
  	
  	if (!defined($ConPool{$ClnSockID}))
  		{
  		warn "Can not connect to \"$RemoteHost\": $@\n";
  		delete($ConPool{$ClnSockID});
  		return;
  		};
  
  	return 1;
  	};

=head1 DESCRIPTION

This module provides simple way to work with number of non-blocking sockets.
It hides most of routine operations with C<IO::Socket::INET>, C<IO::Select>
and provides you the asynchronous Input-Output functions.

Module was designed as a part of a multi-connection SMTP relay
for WinNT platform.

=head1 The C<Net::Socket::NonBlock> methods

=over 4

=item C<new(%PARAMHASH);>

The C<new> method creates the C<SocketsNest> object and returns a handle to it.
This handle is then used to call the methods below.

The C<SocketsNest> itself is the table contains socket handlers, InOut buffers, etc.
C<SocketsNest> also contain a C<IO::Select> object which is common
for all sockets in C<SocketsNest>.

To create new socket you will have to use C<Listen> or C<Connect> methods (see below).
Also, socket could be created automatically during TCP connection accept procedure
inside of C<IO> method.

The I<%PARAMHASH> could contain the following keys:

=over 4

=item Z<>

=over 4

=item C<SelectT>

C<SelectT> is the timeout for C<IO::Select-E<gt>can_read>
and C<IO::Select-E<gt>can_write> function. See L<IO::Select> for details.
Default is 0.1 second.

=item C<SilenceT>

If no data was transferred trough socket for C<SilenceT> seconds
the socket will be closed. Default is 3600 seconds (1 hour). 
If C<SilenceT = 0> socket will nether been closed by timeout.

This value is the default for all sockets created by C<Listen> or C<Connect> method
if another value will not be provided in C<Listen> or C<Connect> parameters.
Also, you will be able to change this parameter for any socket in nest using
C<Properties> method (see below).

=item C<BuffSize>

The size of buffer for C<IO::Socket::INET-E<gt>recv> function (see L<IO::Socket::INET>).
Default if C<POSIX::BUFSIZ> (see C<POSIX>).

This is default for all sockets which will be created and could be overwritten by 
C<Listen>, C<Connect> or C<Properties>.

=item C<InstDeath>

By default, socket become to be unavailable for read not immediately after close request
or IO error but after all data from incoming buffer will be read.
Also, by default all data which was written to output buffer before socket close request
will be flushed to socket before actual closing. You are able to change this behaviour
by set the C<InstDeath> parameter to  I<C<'true'>> value. In this case the socket will be
closed immediately after request, all data in input and output buffer will be lost.

This is default for all sockets which will be created and could be overwritten by 
C<Listen>, C<Connect> or C<Properties>.

=back

=back

=item C<IO();>

The most important method :) This method performs actual socket input-output,
accept incoming connection, close sockets, etc.
You have to call it periodically, as frequently as possible.

C<IO> always returns 1.

=item C<SelectT([$Timeout]);>

If I<C<$Timeout>> is not specified the C<SelectT> method returns a current value of
I<C<SelectT>>.

If I<C<$Timeout>> is specified the C<SelectT> method set the I<C<SelectT>> to the
provided value and returns a previous one.

=back

=head2 The C<Net::Socket::NonBlock> methods for manipulating sockets

=over 4

=item C<Listen(%PARAMHASH);>

The C<Listen> method create new socket listening on I<C<LocalAddr:LocalPort>>.

The C<Listen> take the same list of arguments as C<IO::Socket::INET-E<gt>new>.
The I<Proto> key is required. If I<Proto = 'tcp'> the I<C<Accept>> key is also required.
The C<Accept> key must contain the pointer to the external accept function provided by you.

When the new connection will be detected by listening TCP socket the new socket will be created by
C<IO::Socket::INET-E<gt>accept> function. After that the external I<C<Accept>> function
will be called with just one parameter: the ID for the new socket.
External I<C<Accept>> have to return I<C<true>> value otherwise new socket
will be closed and connection will be rejected.

C<Listen> method returns the I<C<SocketID>>, the symbolic name 
which have to be used for work with particular socket in nest using C<Gets>, C<Puts>,
C<Recv> and C<Properties> methods. In case of problems C<Listen> returns I<C<undef>> value.
I<C<$@>> will contain a error message.

=item C<Connect(%PARAMHASH);>

The C<Connect> method create new socket connected to I<C<PeerAddr:PeerPort>>.

The C<Connect> take the same list of arguments as C<IO::Socket::INET-E<gt>new>.
The I<Proto> key is required.

C<Connect> method returns the I<C<SocketID>>, the symbolic name 
which have to be used for work with particular socket in nest using C<Gets>, C<Puts>,
C<Recv> and C<Properties> methods. In case of problems C<Connect> returns I<C<undef>> value.
I<C<$@>> will contain a error message.

=item I<Important note>

C<Listen> and C<Connect> are synchronous. So if connection establishing take a long time
- for eaxmple because of slow DNS resolving - your program will be frozen for a long time.

=item C<Gets($SocketID, [$MaxLength]);>

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

If socket closed or I<C<$SocketID>> is invalid C<Gets> returns I<C<undef>>.

In list context method returns an array of 3 elements:
[0] - string as in scalar context
[1] - PeerAddr
[2] - PeerPort

Note: C<Gets> is not reading data from the socket but takes it from special buffer filled by
C<IO> method with data read from socket during last call.

If you did not read all the data available in buffer new data will be appended
to the end of buffer.

=item C<Recv($SocketID, [$MaxLength]);>

For TCP sockets the C<Recv> method returns all data available from corresponding socket
if data length is no more than I<C<$MaxLength>>. Otherwise I<C<$MaxLength>> bytes returned.

For non-TCP sockets the C<Recv> works with blocks of data read
from socket by single  C<IO::Socket::INET-E<gt>recv> call. It is necessary to provide correct
C<PeerAddr> and C<PeerPort>. So, if block length is no more than I<C<$MaxLength>>,
the whole block will be returned. If block is too big, I<C<$MaxLength>> bytes will be returned.

Default I<C<$MaxLength>> is socket I<C<BiffSize>>.

If no data available for reading, C<Recv> returns empty string.

If socket is closed or I<C<$SocketID>> is invalid C<Recv> returns I<C<undef>>.

In list context method returns an array of 3 elements:
[0] - string as in scalar context
[1] - PeerAddr
[2] - PeerPort

Note: C<Recv> is not reading data from the socket but takes it from special buffer filled by
C<IO> method.

=item C<Read($SocketID, [$MaxLength]);>

This method is little bit eclectic but I found it's useful.

If string I<C<"\n">> is presented in the buffer this method will act as C<Gets> method.
Otherwise it will act as C<Recv>.

I<C<$MaxLength>> for C<Read> have to be no more than C<32766>.
It will be adjusted automaticaly otherwise.

=item C<Puts($SocketID, $Data, $PeerAddr, $PeerPort);>

The C<Puts> method puts data to the corresponding socket outgoing buffer.

I<C<$PeerAddr:$PeerPort>> pair is the destination which I<C<$Data>> must be sent.
If not specified these fields will be taken from socket properties.
I<C<$PeerAddr:$PeerPort>> will be ignored on TCP sockets.

If socket closed or I<C<$SocketID>> is invalid C<Recv> returns I<C<undef>>.
Otherwise it returns 1.

Note: C<Puts> is not writing data directly to the socket but puts it to the special buffer
which will be flushed to socket by C<IO> method during next call.

=item C<Send($SocketID, $Data);>

Just a synonym for C<Puts>.

=item C<PeerAddr($SocketID);>

For TCP sockets the C<PeerAddr> method returns the IP address which is socket connected to or
empty string for listening sockets.

For non-TCP sockets the C<PeerAddr> method returns the IP address which was used for sending 
last time or IP address which is corresponding to data read by last C<Gets> or C<Recv> call.

If socket closed or I<C<$SocketID>> is invalid C<PeerAddr> returns I<C<undef>>.

=item C<PeerPort($SocketID);>

For TCP sockets the C<PeerPort> method returns the IP address which is socket connected to or
empty string for listening sockets.
I<C<undef>>

For non-TCP sockets the C<PeerPort> method returns the port which was used for sending 
last time or port which is corresponding to data read by last C<Gets> or C<Recv> call.

If socket closed or I<C<$SocketID>> is invalid C<PeerPort> returns I<C<undef>>.

=item C<LocalAddr($SocketID);>

The C<LocalAddr> method returns the IP address for this end of the socket connection.

If socket closed or I<C<$SocketID>> is invalid C<LocalAddr> returns I<C<undef>>.

=item C<LocalPort($SocketID);>

The C<LocalPort> method returns the IP address for this end of the socket connection.

If socket closed or I<C<$SocketID>> is invalid C<LocalPort> returns I<C<undef>>.

=item C<Handle($SocketID);>

The C<Handle> method returns the handle to the C<IO::Socket::INET> object
associated with I<C<$SocketID>> or I<C<undef>> if I<C<$SocketID>> is invalid or socket closed.

=item C<Properties($SocketID, [%PARAMHASH]);>

The C<Properties> method returns the hash in list context or pointer to the hash in scalar context.
Hash itself is containing socket properties which are:

=over 4

=item Z<>

=over 4

=item C<Handle>

The handle to the socket associated with I<C<$SocketID>>. Read-only.

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

The socket time when socket was sending or receiving data last time. Read-only.

=item C<PeerAddr>

The value is the same as returned by C<PeerAddr> method. Read-only.

=item C<PeerPort>

The value is the same as returned by C<PeerPort> method. Read-only.

=item C<LocalAddr>

The value is the same as returned by C<LocalAddr> method. Read-only.

=item C<LocalPort>

The value is the same as returned by C<LocalPort> method. Read-only.

=item C<SilenceT>

If no data was sent to or received from socket for I<C<SilenceT>> the socket
will be closed.

=item C<BuffSize>

The size of buffer for C<IO::Socket::INET-E<gt>recv> function.

=item C<InstDeath>

The current state of I<C<instant death>> flag. See C<new> for details.

=item C<Accept>

The pointer to the external C<Accept> function. See C<Listen> for details.

=back

=back

The following parameters could be changed if new value will be provided in the I<C<%PARAMHASH>>:

=over 4

=item Z<>

=over 4

=item C<SilenceT>

=item C<BuffSize>

=item C<InstDeath>

=item C<Accept>

Note: you will be able to set C<Accept> property only for TCP listening sockets.

=back

=back

=item C<Close($SocketID);>

Put the "close" request for the socket I<C<$SocketID>>.
The actual removing will be done by C<IO> method during next call.

Remember: it is important to call C<Close> for all socket which have to be removed
even they become to be unavailable because of I<C<send()>> or I<C<recv()>> error.

=back

=item C<SafeStr($Str);>

Just change all dangerous symbols (C<\x00-\x1F> and C<\xFF>) in a string to their
hexadecimal codes and returns the updated string. Nothing relative to sockets but
can be very usefull for logging pourposes

=back

=head2 EXPORT

C<SafeStr>

=head1 AUTHOR

Daniel Podolsky, E<lt>tpaba@cpan.orgE<gt>

=head1 SEE ALSO

L<IO::Socket::INET>, L<IO::Select>.

=cut
