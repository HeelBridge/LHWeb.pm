package main;
use strict;
use warnings;
use Data::Dumper;


#my %LHWeb_gets = (
#	"Test"		=> "getTest"
#	"whatyouneed"	=> "try sometimes",
#	"satisfaction"  => "no"
#);

#my %LHWeb_sets = (
#	"Discover"	=> "."
#);




my $LHWeb_sets="Reconnect";
my $LHWeb_gets="Channels";

sub LHWeb_Initialize($) {
    my ($hash) = @_;

    Log3 $hash,  4, "LHWeb_Initialize";

    require "$attr{global}{modpath}/FHEM/DevIo.pm";


    $hash->{ReadFn}  = "LHWeb_Read";
    $hash->{WriteFn} = "LHWeb_Write";
    $hash->{ReadyFn} = "LHWeb_Ready";

    $hash->{DefFn}      = 'LHWeb_Define';
    $hash->{UndefFn}    = 'LHWeb_Undef';
    $hash->{SetFn}      = 'LHWeb_Set';
    $hash->{GetFn}      = 'LHWeb_Get';
    $hash->{AttrFn}     = 'LHWeb_Attr';
    $hash->{ReadFn}     = 'LHWeb_Read';
    $hash->{ShutdownFn} = 'LHWeb_Shutdown';

    $hash->{AttrList} =
          "Test "
        . $readingFnAttributes;

}



sub LHWeb_Ready($){
    my ($hash) = @_;
    
    Log3 $hash,  4, "LHWeb_Ready";

    if(!$hash){ return 0; }
    if(!$hash->{TCPDev}){ return 0; }
    return 1;
}


sub LHWeb_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    my $ret = "";
    
    Log3 $hash,  4, "LHWeb_Define";

    if(int(@param) < 4) {
        return "too few parameters: define <name> LHWeb <ip-address> <channel>";
    }

    
    $hash->{name} = $param[0];
    $hash->{port} = 23;    
    $hash->{DeviceName} = $param[2].":23";
    $hash->{channel} = $param[3];


    $ret = DevIo_OpenDev($hash, 0, "LHWeb_Init");
    if($ret){ Log3 $hash,  4, "LHWeb_Define ret=$ret"; }

    #readingsSingleUpdate ( $hash, "state", "defined", 1 );
    
    InternalTimer(gettimeofday()+31, "LHWeb_Ping", $hash, 0);
    readingsSingleUpdate ( $hash, ".lastMessage", gettimeofday(), 0 );

    return $ret;
}

sub LHWeb_Ping($){
    my ($hash) = @_;

    my $lastMsg=ReadingsVal($hash->{NAME}, ".lastMessage", "0");
    my $blackout=gettimeofday()-$lastMsg;
    Log3 $hash, 4, "LHWeb_Ping: LastMsg=".$lastMsg;
    Log3 $hash, 4, "LHWeb_Ping: LastMsg=".(gettimeofday()-$lastMsg);

    if($blackout > 240){
        Log3 $hash, 4, "LHWeb_Ping: Connection timed out. Reconnecting..";
        LHWeb_Reopen($hash);
    }elsif($blackout>120){
        Log3 $hash, 4, "LHWeb_Ping: No answer from device for more than 2min. Stale connection?";
    }else{
        LHWeb_SimpleWrite($hash, "rssi");
    }
    InternalTimer(gettimeofday()+30, "LHWeb_Ping", $hash, 0);
}


sub LHWeb_SimpleWrite(@)
{

  my ($hash, $msg) = @_;
  return if(!$hash);



  if(!$hash->{TCPDev}){
    Log3 $hash, 3, "LHWeb_SimpleWrite: No TCP device found";
    if($hash->{cl} && $hash->{asyncCmd} && $hash->{asyncCmd} ne ""){
        asyncOutput( $hash->{cl}, "Error:\nDevice is not connected.\nCommand cannot be executed!" );
    }

    return 0;
  }

  Log3 $hash,  4, "LHWeb_SimpleWrite msg=".$msg;

  syswrite($hash->{TCPDev}, $msg);

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}



sub LHWeb_Init(){
    my $hash = shift;
    my $name = $hash->{NAME};

    Log3 $hash,  4, "LHWeb_Init";

    LHWeb_SimpleWrite($hash, "version");
    sleep(1);
    LHWeb_SimpleWrite($hash, "rssi");
    sleep(1);
    LHWeb_SimpleWrite($hash, "channel ".$hash->{channel});
}


sub LHWeb_Read($){
  my ($hash) = @_;

  my $new_sets="";
  my $async_ret="";
  
  Log3 $hash,  4, "LHWeb_Read";
        
  my $buf = DevIo_SimpleRead($hash);
  if(!$buf){ $buf=""; }
  my $buf_clean=$buf;
  $buf_clean =~ s/\n/\\n/g;
  Log3 $hash,  4, "LHWeb_Read: buf=".$buf_clean;
  

  return "" if(!defined($buf));
  return "" if($buf eq "");
  
  foreach my $line (split('\n', $buf)) {

    my($val1, $val2, $val3)=split(' ', $line);    

    $val1="" if(!$val1);    
    $val2="" if(!$val2);    
    $val3="" if(!$val3);    

    Log3 $hash,  4, "LHWeb_Read: val1=$val1 val2=$val2 val3=$val3";

    if($val2 eq $hash->{channel}){
        if($val1 eq "state"){
            readingsSingleUpdate ( $hash, "state", $val3, 1 );
        }
        if($val1 eq "channel"){
            if($val3){ $new_sets.=$val3." "; }
            if($hash->{asyncCmd} and $hash->{asyncCmd} eq "channels"){
                $async_ret.=$val2."\n";
            }
        }
    }elsif($val1 eq "version"){
        #$hash->{version}=$val2." ".$val3;
        readingsSingleUpdate ( $hash, "version", $val2." ".$val3, 1 );
    }elsif($val1 eq "rssi"){
        $hash->{RSSI} = $val2;
    }

    if($val1 ne ""){
        readingsSingleUpdate ( $hash, ".lastMessage", gettimeofday(), 0 );
    }
    
    
  }
  
  
  if($new_sets ne ""){
    $LHWeb_sets=$new_sets."Reconnect";
  }
    

  if($hash->{cl} && $hash->{asyncCmd} && $hash->{asyncCmd} ne ""){
    asyncOutput( $hash->{cl}, $async_ret );
  }
  undef $hash->{asyncCmd};

}


sub LHWeb_Write($$$){
  my ($hash,$fn,$msg) = @_;
  
  Log3 $hash,  4, "LHWeb_Write";

} 



sub LHWeb_Undef($$) {
    my ($hash, $arg) = @_; 

    Log3 $hash,  4, "LHWeb_Undef";

    DevIo_CloseDev($hash);

    return 1;
}

sub LHWeb_SetState(@){
  my ($hash, $opt, $val) = @_;

  LHWeb_SimpleWrite($hash, "set ".$hash->{channel}." $opt $val\n");
  readingsSingleUpdate ( $hash, "state", "set-$opt", 1 );
}

sub LHWeb_Get($@) {
	my ($hash, @param) = @_;
	
	return '"get LHWeb" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
    
	Log3 $hash,  4, "LHWeb_get: name=$name opt=$opt";

	if($opt eq "Channels"){
	    LHWeb_SimpleWrite($hash, "channel\n");
	    if($hash->{CL} && $hash->{CL}->{canAsyncOutput} ){
	        Log3 $hash, 4, "LHWeb_get: starting aysync get";
	        $hash->{cl}=$hash->{CL};
	        $hash->{asyncCmd}="channels";
	    }
	    return undef;
	}elsif($opt eq "?"){
	    return "Unknown argument $opt, choose one of ".$LHWeb_gets;
	    return $LHWeb_gets;
	}else{
	    return "Unknown argument $opt, choose one of ".$LHWeb_gets;
	}

}

sub LHWeb_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set LHWeb" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
	my @sets=split(/ /,$LHWeb_sets);
	
	Log3 $hash,  4, "LHWeb_set: name=$name opt=$opt value=$value";
	
	if($opt eq "?"){
	    return "Unknown argument $opt, choose one of ".$LHWeb_sets;
        }elsif($opt eq "Reconnect"){
            LHWeb_Reopen($hash);
            return undef;
	}elsif(grep( /^$opt$/, @sets )){
	    LHWeb_SetState($hash, $opt, $value);
	    return undef;
	}else{
	    return "Unknown argument $opt, choose one of ".$LHWeb_sets;
	}
    
}


sub LHWeb_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        #if($attr_name eq "formal") {
	#		if($attr_value !~ /^yes|no$/) {
	#		    my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
	#		    Log3 $hash,  3, "Hello: ".$err;
	#		    return $err;
	#		}
	#	} else {
	#	    #return "Unknown attr $attr_name";
	#	}
	}
	return undef;
}


sub LHWeb_Reopen($){
  my ($hash) = @_;

  Log3 $hash,  4, "LHWeb_Reopen";

  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 1, "LHWeb_Init");
}


sub LHWeb_Shutdown($)
{
    my ($hash) = @_;

    Log3 $hash,  4, "LHWeb_Shutdown";

    DevIo_CloseDev($hash);
    return undef;
}




1;

=pod
=begin html

<a name="LHWeb"></a>
<h3>LHWeb</h3>
<ul>
    The <i>LHWeb</i> lets you easily include ESP8266 devices which use the LHWeb library into fhem.
    <br><br>
    The LHWeb library for the ESP8266 module handles most, if not all, of web server handling so you 
    can concentrate on the pure logic of your project. It also includes interfaces to control the
    module via serial line and TCP sockets. The LHWeb fhem module uses those sockets to talk to
    and control the ESP8266.
    <br><br>
    <a name="LHWebdefine"></a>
    <b>Define</a>
    <ul>
      <code>define &lt;name&gt; LHWeb &lt;address&gt; &lt;channel&gt;</code>
      <ul>
        <li><code>&lt;address&gt;</code><br>The IP-address of the running module</li>
        <li><code>&lt;channel&gt;</code><br>The channel on the ESP you want to use. Which channels are available depends 
        on the program running on the ESP.</li>
      </ul>
      <br><br>      
      Example: <code>define wifi_light 192.168.0.10 lamp</code>
   </ul>
</ul>

=end html

=cut
