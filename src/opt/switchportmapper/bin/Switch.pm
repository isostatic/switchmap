package Switch;

use strict;
use SNMP::Info 3.30;
use Log::Log4perl qw(get_logger);
#use Data::Dumper;
use GetChassisModel;
use PopulateEtherChannels;
use ModuleList;
use PopulatePorts;
use Socket;  # for inet_ntoa


sub new {
  my $type = shift;
  my $name = shift;
  my $logger = get_logger('log3');
  $logger->debug("called");

  my $this = {};
  my $ShortName = $name;
  $ShortName =~ s/$ThisSite::DnsDomain//;         # remove the trailing DNS domain
  $this->{ChassisModel}          = 'unknown';
  $this->{EtherChannels}         = {};            # hash of EtherChannel objects, keys are IfIndexes of parent ports
  $this->{FullName}              = $name;
  $this->{HasStackMIB}           = $Constants::FALSE;
  $this->{IfMacs}                = {};            # keys are MAC addresses of the ports, values are meaningless
  $this->{IPaddr}                = '';
  $this->{ModuleList}            = 0;
  $this->{Name}                  = $ShortName;
  $this->{NbrModules}            = 0;             # 3524s and 1912Cs don't have modules, all others at NCAR do
  $this->{NbrUnusedPorts}        = 0;
  $this->{PortCountByVlan}       = {};            # keys are Vlan numbers
  $this->{PortsByIfNbr}          = {};            # keys are ifIndexes
  $this->{Ports}                 = {};            # keys are port names
  $this->{ProductDescription}    = 'unknown';
  $this->{ProductName}           = 'unknown';
  $this->{SnmpCommunityString}   = '';
  $this->{SnmpSysContact}        = 'unknown';
  $this->{SnmpSysDescr}          = '';
  $this->{SnmpSysLocation}       = 'unknown';
  $this->{SnmpSysName}           = 'unknown';
  $this->{SnmpSysObjectId}       = '';
  $this->{UnusedPortCountByVlan} = {};            # keys are Vlan numbers
  $this->{Vlans}                 = {};            # keys are Vlan numbers, values are the number of ports in the Vlan
  $this->{SnmpSysUptime}         = '';

  $logger->debug("returning");
  return bless $this;
}


sub GetName {
  my $this = shift;
  return $this->{Name};
}


sub GetChassisModel {
  my $this = shift;
  return $this->{ChassisModel};
}


sub GetSysDescription {
  my $this = shift;
  return $this->{SnmpSysDescr};
}


sub GetContact {
  my $this = shift;
  return $this->{SnmpSysContact};
}


sub GetSysName {
  my $this = shift;
  return $this->{SnmpSysName};
}

# getter for new field
sub GetIPaddr {
  my $this = shift;
  return $this->{IPaddr}
}

sub GetLocation {
  my $this = shift;
  return $this->{SnmpSysLocation};
}


sub GetProductName {
  my $this = shift;
  return $this->{ProductName};
}


sub GetProductDescription {
  my $this = shift;
  return $this->{ProductDescription};
}


sub GetPrintableModules {
  my $this = shift;
  return $this->{ModuleList}->GetPrintableModuleList;
}


sub GetSysUptime {
  my $this = shift;
  return $this->{SnmpSysUptime};
}


#
# Net::SNMP returns MAC tables as a hash with the values in binary format.
# This subroutine converts such a hash into another hash with the values
# in ASCII.
#
sub TranslateSnmpMacs {
  my $InTable = shift;
  my $OutTable = shift;
  foreach my $interface (keys %{$InTable}) {
    my $mac = unpack 'H12', $$InTable{$interface};
    next if $mac eq '';
    next if $mac eq '000000000000';
    $OutTable->{$mac}++;
  }
}


sub DbgPrintEtherchannel ($) {
  my $Switch = shift;
  my $logger = get_logger('log3');

  foreach my $ParentIfIndex (sort keys %{$Switch->{EtherChannels}}) {
    my $EtherChannel = $Switch->{EtherChannels}{$ParentIfIndex};
    my $outstring = "parent = $ParentIfIndex, children =";
    foreach my $ChildPort (@{$EtherChannel->{ChildPorts}}) {
      my $ChildName = $ChildPort->{Name};
      $outstring .= " $ChildName";
    }
    $logger->debug($outstring);
  }
}


#
# Given a switch object, do SNMP to the switch and fill in the data
# fields in the object.
#
sub PopulateSwitch ($) {
  my $this = shift;
  my $logger = get_logger('log3');
  $logger->debug("called");

  my $SwitchName = $this->{Name};
  my $Session;
  if (!SwitchUtils::OpenSnmpSession($SwitchName,                   # passed in
                                    \$Session,                     # returned
                                    \$this->{SnmpCommunityString}, # returned
                                    \$this->{SnmpSysObjectId})) {  # returned
    $logger->error("couldn't open SNMP session to $SwitchName, skipping this switch");
    return $Constants::FAILURE;
  }

  my $switchTimer = new Timer "in PopulateSwitch, getting data from $SwitchName", $Timer::DEVICE_NAME;
  $switchTimer->start;

  $this->{ProductName}        = MibConstants::getChassisName   ($this->{SnmpSysObjectId});
  $this->{ProductDescription} = MibConstants::getChassisComment($this->{SnmpSysObjectId});

  my $sysDescrOid    = '1.3.6.1.2.1.1.1.0';
  my $sysUptimeOid   = '1.3.6.1.2.1.1.3.0';
  my $sysContactOid  = '1.3.6.1.2.1.1.4.0';
  my $sysNameOid     = '1.3.6.1.2.1.1.5.0';
  my $sysLocationOid = '1.3.6.1.2.1.1.6.0';
  my $result = $Session->get_request(-varbindlist => [$sysDescrOid,
                                                      $sysUptimeOid,
                                                      $sysContactOid,
                                                      $sysNameOid,
                                                      $sysLocationOid]);
  if (!defined($result)) {
    $logger->warn("$SwitchName: Couldn't get the sysDescr, sysUptimeOid, sysContact, sysName and sysLocation");
    return $Constants::FAILURE;
  }
  $this->{SnmpSysDescr}    = $result->{$sysDescrOid};
  $this->{SnmpSysContact}  = $result->{$sysContactOid};
  $this->{SnmpSysName}     = $result->{$sysNameOid};
  $this->{SnmpSysLocation} = $result->{$sysLocationOid};
  $this->{SnmpSysUptime}   = $result->{$sysUptimeOid};

  $logger->debug('sysDescr = "'    . $this->{SnmpSysDescr}    . '"');
  $logger->debug('sysContact = "'  . $this->{SnmpSysContact}  . '"');
  $logger->debug('sysName = "'     . $this->{SnmpSysName}     . '"');
  $logger->debug('sysLocation = "' . $this->{SnmpSysLocation} . '"');
  $logger->debug('sysUptime = "'   . $this->{SnmpSysUptime}   . '"');

  my $packed_ip = gethostbyname($this->{FullName});
  $this->{IPaddr} = inet_ntoa($packed_ip) if defined $packed_ip;

  my $status = GetChassisModel::GetChassisModel($this, $Session);
  if (!$status) {
    $logger->warn("Couldn't get the switch type from $SwitchName, skipping this switch");
    return $Constants::FAILURE;
  }

  #
  # When you ask a switch for the MAC addresses in a bridge table,
  # some switches will return the MAC addresses of the switch's own
  # interfaces along with the MAC addresses of the things that are
  # outside the switch.  No one is interested in the MAC addresses of
  # interfaces on the switch itself, so we have to explicitly ignore
  # them when we see them.  In order to ignore them, we have to know
  # which ones they are...
  #
  my %ifPhysAddress;
  $status = SwitchUtils::GetSnmpTable($Session,
                                      'ifPhysAddress',
                                      $Constants::INTERFACE,
                                      \%ifPhysAddress);
  if ($status == $Constants::SUCCESS) {
    TranslateSnmpMacs \%ifPhysAddress, $this->{IfMacs};
    # SwitchUtils::DbgPrintHash('IfMacs', $this->{IfMacs});
  } else {
    $logger->warn("$SwitchName: Couldn't get the ifPhysAddress table");
  }

  $this->{ModuleList} = new ModuleList;
  $this->{NbrModules} = $this->{ModuleList}->PopulateModuleList($Session);

  PopulatePorts::PopulatePorts($this, $Session);

  #
  # build $this->{PortsByIfNbr}
  #
  foreach my $PortName (keys %{$this->{Ports}}) {
    my $Port = $this->{Ports}{$PortName};
    my $IfNbr = $Port->{IfNbr};
    $logger->debug("setting \$this\{PortsByIfNbr\}\{$IfNbr\} for $PortName");
    $this->{PortsByIfNbr}{$IfNbr} = $Port;
    my $VlanNbr = $Port->{VlanNbr};
    if (defined $VlanNbr) {     # if the port is in a VLAN
      $this->{PortCountByVlan}{$VlanNbr}++;
      $this->{UnusedPortCountByVlan}{$VlanNbr}++ if $Port->{Unused};
    }
  }

  #
  # Get the etherchannel data, if the switch has etherchannels.
  #
  PopulateEtherChannels::PopulateEtherChannels($Session, $this);
#  DbgPrintEtherchannel($this);

  $Session->close;
  
  # if we didn't get the table that maps ports to Vlans, try SNMP::Info.
  my $vcount = keys %{$this->{Vlans}};
  if ($vcount == 0) {
    $logger->debug("Ok, there's no mapping of port names to VLANs, so I'll try SNMP::Info");
    my $session = new SNMP::Info (
                                  AutoSpecify => 1,
                                  Debug       => 0, # note: setting this to 1 is interesting
                                  DestHost    => $SwitchName,
                                  Community   => $this->{SnmpCommunityString},
                                  MibDirs     => [ '/opt/switchportmapper/mibs/cisco', '/opt/switchportmapper/mibs/rfc', '/opt/switchportmapper/mibs/juniper', '/opt/switchportmapper/mibs/foundry', '/opt/switchportmapper/mibs/mikrotik', '/opt/switchportmapper/mibs/hp', '/opt/switchportmapper/mibs/h3c'],
                                  Version     => 2
                                 );
    if (!defined $session) {
      die "couldn't open SNMP::Info session to $SwitchName, perhaps wrong device FQDN or wrong community\n";
    }

    my $err = $session->error();
    die "SNMP Community or Version probably wrong connecting to $SwitchName. $err\n" if defined $err;

    my $class = $session->class();
    $logger->debug("Using SNMP::Info, which says the device subclass is $class");

    # my $interfaces    = $session->interfaces();
    # my $count = keys %$interfaces;
    # $logger->debug("Using SNMP::Info, got $count interfaces");
#   SwitchUtils::DbgPrintHash('interfaces', $interfaces);

    # my $duplextable   = $session->i_duplex();
    # $count = keys %$duplextable;
    # $logger->debug("Using SNMP::Info, got $count duplextable entries");
#   SwitchUtils::DbgPrintHash('duplextable', $duplextable);

    # my $labels         = $session->i_name();
    # $count = keys %$labels;
    # $logger->debug("Using SNMP::Info, got $count labels");
#    SwitchUtils::DbgPrintHash('labels', $labels);

    my $vlans = $session->i_vlan();
    my $count = keys %$vlans;
    $logger->debug("Using SNMP::Info, got $count i_vlan entries");
    
    # $logger->debug("getting i_vlan_membership (this takes a while)...");
    # my $vlan_members         = $session->i_vlan_membership();
    # $count = keys %$vlan_members;
    # $logger->debug("Using SNMP::Info, got $count vlan_membership entries");
    # print Dumper($vlan_members);

    foreach my $PortName (Portically::PortSort keys %{$this->{Ports}}) {
      my $Port = $this->{Ports}{$PortName};
      my $IfNbr = $Port->{IfNbr};
      $logger->debug("loop: PortName = $PortName, IfNbr = $IfNbr");

      if (defined $$vlans{$IfNbr}) {
        $logger->debug("loop: setting VlanNbr to $vlans->{$IfNbr}");
        $Port->{VlanNbr} = $vlans->{$IfNbr};
      }

      # if (exists $$vlan_members{$IfNbr}) {
      #   my $arrSize = @{ $$vlan_members{$IfNbr} };
      #   if ($arrSize == 1) {
      #     $logger->debug("loop: setting VlanNbr to ");
      #     $Port->{VlanNbr} = @{ $$vlan_members{$IfNbr} }[0];
      #   } else {
      #     $logger->debug("multiple VLANs on port, must be a trunk, skipping setting the VlanNbr");
      #   }
      # }
    }

#    foreach my $i (sort keys %{$vlan_members}) {
#      $logger->debug("vlan_membership{$i} = @{ $$vlan_members{$i} }");
      # my $vlan = 'undef';
      # if (exists $$vlan_members{$i}) {
      #   $vlan = "@{ $$vlan_members{$i} }";
      # }
#    }

    $session->close();
  } else {
    $logger->debug("Ok, I have a mapping from port names to VLANs, so I didn't use SNMP:::Info");
  }
  SwitchUtils::DbgPrintHash('Vlans', $this->{Vlans});
  
  $switchTimer->stop;
  $logger->debug("returning success");
  return $Constants::SUCCESS;
}                               # PopulateSwitch

1;
