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

    require "$attr{global}{modpath}/FHEM/DevIo.pm";


    $hash->{ReadFn}  = "LHWeb_Read";
    $hash->{WriteFn} = "LHWeb_Write";
#    $hash->{ReadyFn} = "LHWeb_Ready";

    $hash->{DefFn}      = 'LHWeb_Define';
    $hash->{UndefFn}    = 'LHWeb_Undef';
    $hash->{SetFn}      = 'LHWeb_Set';
    $hash->{GetFn}      = 'LHWeb_Get';
    $hash->{AttrFn}     = 'LHWeb_Attr';
    $hash->{ReadFn}     = 'LHWeb_Read';

    $hash->{AttrList} =
          "Test "
        . $readingFnAttributes;

}



sub LHWeb_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
    my $ret = "";
    
    Log 3, "LHWeb_Define";

    if(int(@param) < 4) {
        return "too few parameters: define <name> LHWeb <ip-address> <channel>";
    }
    
    $hash->{name} = $param[0];
    $hash->{port} = 23;    
    $hash->{DeviceName} = $param[2].":23";
    $hash->{channel} = $param[3];

    $ret = DevIo_OpenDev($hash, 0, "LHWeb_Init");
    Log 4, "LHWeb_Define: ret=$ret";

    readingsSingleUpdate ( $hash, "state", "defined", 1 );

    return $ret;
}


sub LHWeb_SimpleWrite(@)
{

  my ($hash, $msg) = @_;
  return if(!$hash);

  Log 4, "LHWeb_SimpleWrite: ".$msg;

  syswrite($hash->{TCPDev}, $msg);

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}



sub LHWeb_Init(){
    my $hash = shift;
    my $name = $hash->{NAME};

    Log 4, "LHWeb_Init";

    LHWeb_SimpleWrite($hash, "version");
    sleep(1);
    LHWeb_SimpleWrite($hash, "channel ".$hash->{channel});
}


sub LHWeb_Read($){
  my ($hash) = @_;

  my $new_sets="";
  
  Log 4, "LHWeb_Read";
        
  my $buf = DevIo_SimpleRead($hash);
  Log 4, "Buf=$buf";
  

  return "" if(!defined($buf));
  return "" if($buf eq "");
  
  foreach my $line (split('\n', $buf)) {

    my($val1, $val2, $val3)=split(' ', $line);    
    
    Log 4, "vals: $val1, $val2, $val3";

    if($val2 eq $hash->{channel}){
        if($val1 eq "state"){
            readingsSingleUpdate ( $hash, "state", $val3, 1 );
        }
        if($val1 eq "channel"){
            $new_sets.=$val3." ";
        }
    }elsif($val1 eq "version"){
        $hash->{version}=$val2." ".$val3;
    }
  }
  
  if($new_sets ne ""){
    $LHWeb_sets=$new_sets."Reconnect";
  }
    
}


sub LHWeb_Write($$$){
  my ($hash,$fn,$msg) = @_;
  
  Log 4, "LHWeb_Write";

} 



sub LHWeb_Undef($$) {
    my ($hash, $arg) = @_; 
    # nothing to do
    return undef;
}

sub LHWeb_SetState(@){
  my ($hash, $val) = @_;

  LHWeb_SimpleWrite($hash, "set ".$hash->{channel}." $val\n");
  readingsSingleUpdate ( $hash, "state", "set-$val", 1 );
}

sub LHWeb_Get($@) {
	my ($hash, @param) = @_;
	
	return '"get LHWeb" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
    
	Log 4, "LHWeb_get: name=$name, opt=$opt";

	if($opt eq "Channels"){
	    LHWeb_SimpleWrite($hash, "channel ".$hash->{channel}."\n");
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
	
	Log 4, "LHWeb_set: name=$name, opt=$opt, value=$value";
	
	if($opt eq "?"){
	    return "Unknown argument $opt, choose one of ".$LHWeb_sets;
        }elsif($opt eq "Reconnect"){
            LHWeb_Reopen($hash);
            return undef;
	}elsif(grep( /^$opt$/, @sets )){
	    LHWeb_SetState($hash, $opt);
	    return undef;
	}else{
	    return "Unknown argument $opt, choose one of ".$LHWeb_sets;
	}
    
}


sub LHWeb_Attr(@) {
	my ($cmd,$name,$attr_name,$attr_value) = @_;
	if($cmd eq "set") {
        if($attr_name eq "formal") {
			if($attr_value !~ /^yes|no$/) {
			    my $err = "Invalid argument $attr_value to $attr_name. Must be yes or no.";
			    Log 3, "Hello: ".$err;
			    return $err;
			}
		} else {
		    #return "Unknown attr $attr_name";
		}
	}
	return undef;
}


sub LHWeb_Reopen($){
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 1, "LHWeb_Init");
}

1;

=pod
=begin html

<a name="LHWeb"></a>
<h3>LHWeb</h3>
<ul>
    <i>LHWeb</i> manages the network connections to and from all LHWeb devices. It acts kind of like a CUL or JeeLink.<br>
    For each individual LHWeb device you also need to define a seperate LHWeb in fhem.
</ul>

=end html

=cut
