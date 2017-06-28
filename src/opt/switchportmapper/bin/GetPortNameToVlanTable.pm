package GetPortNameToVlanTable;

use strict;
use Log::Log4perl qw(get_logger);


#
# Set the Vlan field for each port.
#
sub GetPortNameToVlanTable ($$$$$) {
  my $Switch         = shift;   # passed in
  my $Session        = shift;   # passed in
  my $IfToIfNameRef  = shift;   # passed in
  my $PortIfIndexRef = shift;   # passed in
  my $VlansRef       = shift;   # passed in empty, filled by this function
  my $logger = get_logger('log5');
  $logger->debug("called");

  my $doneGettingTable = 0;
  
  # On switches that support the Cisco Stack MIB, like 6509s, the
  # port-to-vlan table is in the vlanPortVlan table.
  if (!$doneGettingTable) {
    $logger->info("getting port-to-VLAN mapping table from Cisco Stack MIB...");
    my %vlanPortVlan;
    my $status = SwitchUtils::GetSnmpTable($Session,
                                           'vlanPortVlan',
                                           $Constants::PORT,
                                           \%vlanPortVlan);
    if ($status == $Constants::SUCCESS) {
      #    print Dumper(%vlanPortVlan);
      my $NbrPorts = keys %vlanPortVlan;
      $logger->debug("got $NbrPorts values from port-to-VLAN mapping table named vlanPortVlan");
      foreach my $PortName (keys %vlanPortVlan) {
        if ((exists $PortIfIndexRef->{$PortName}) and ($PortIfIndexRef->{$PortName} != 0)) {
          $VlansRef->{$IfToIfNameRef->{$PortIfIndexRef->{$PortName}}} = $vlanPortVlan{$PortName};
        }
      }
      $doneGettingTable = 1;
    }
  }
    
  if (!$doneGettingTable) {
    # If we made it to here, we couldn't reach the switch or it's real
    # slow or it doesn't do the Cisco Stack MIB.  It might even be a Cisco
    # switch that doesn't support the Cisco Stack MIB, like a 3524.
    # On such switches, the port-to-vlan table is in a combination of
    # tables: trunk ports are in the vlanTrunkPortNativeVlan table in
    # the ciscoVtpMIB and non-trunk ports are in the vmVlan table in
    # the ciscoVlanMembershipMIB.  Some 3524s may support neither
    # because no trunks are configured at all.
    $logger->debug("it doesn't support the Cisco Stack MIB, trying the Cisco VTP MIB (vmVlan)");
    my %vmVlan;
    my $status = SwitchUtils::GetSnmpTable($Session,
                                           'vmVlan',
                                           $Constants::INTERFACE,
                                           \%vmVlan);
    if ($status == $Constants::SUCCESS) {
      my $SwitchName = GetName $Switch;
      #      SwitchUtils::DbgPrintHash('vmVlan', \%vmVlan);
      foreach my $ifNbr (keys %vmVlan) {
        my $PortName = $$IfToIfNameRef{$ifNbr};
        if (defined $PortName) {
          my $vlan = $vmVlan{$ifNbr};
          $logger->debug("$SwitchName: setting \$\$VlansRef{$PortName} to \$vmVlan{$ifNbr} = $vlan");
          $$VlansRef{$PortName} = $vlan;
        } else {
          $logger->debug("$SwitchName: for \$ifNbr = \"%ifNbr\", \$PortName is not defined, skipping");
        }
      }
      $doneGettingTable = 1;
    }
  }
      
  if (!$doneGettingTable) {
    # If we made it to here, we couldn't reach the switch or it's real
    # slow or it doesn't do the Cisco Stack MIB or Ciso VTP MIB.  Try
    # the Juniper MIBs.
    $logger->debug("it doesn't support the Cisco VTP MIB, trying the Juniper MIB (jnxE4bxVlanPortAccessMode)");
    my %jnxExVlanPortAccessMode;
    my $status = SwitchUtils::GetSnmpTable($Session,
                                        'jnxExVlanPortAccessMode',
                                        $Constants::PORT,
                                        \%jnxExVlanPortAccessMode);
    if ($status == $Constants::SUCCESS) {
      $logger->debug("it supports the Juniper VLAN MIB");

      my %jnxExVlanTag;
      $status = SwitchUtils::GetSnmpTable($Session,
                                          'jnxExVlanTag',
                                          $Constants::INTERFACE,
                                          \%jnxExVlanTag);
      if ($status == $Constants::SUCCESS) {
        $logger->debug("got the jnxExVlanTag table");
        foreach my $vlanId (sort keys %jnxExVlanTag) {
          $logger->debug("\%jnxExVlanTag{$vlanId} = \"$jnxExVlanTag{$vlanId}\"");
        }
      }

      foreach my $vlanPort (sort keys %jnxExVlanPortAccessMode) {
        my ($vlanId, $BifNbr) = split '/', $vlanPort;
        $logger->debug("   \$vlanport = \"$vlanPort\",  vlanId = $vlanId, \$BifNbr = $BifNbr");

        if (exists $$IfToIfNameRef{$BifNbr}) {
          my $PortName = $$IfToIfNameRef{$BifNbr};
          my $vlanNbr = $jnxExVlanTag{$vlanId};
          $logger->debug("   port $PortName is in VLAN $vlanNbr");
          $$VlansRef{$PortName} = $jnxExVlanTag{$vlanId};
        }
      }
      $doneGettingTable = 1;
    }
  }


  # Here was my attempt to read and parse the Q_Bridge MIB. I gave up
  # on this in favor of SNMP::Info, but I kept this code in case
  # SNMP::Info proves to be too hard to integrate into Switchmap.
  
  # if (!$doneGettingTable) {
  #   # If we made it to here, it doesn't support the jnxExVlanTag,
  #   # which Juniper is phasing out in favor of dot1qVlanStaticTable.
  #   $logger->debug("it doesn't support the Juniper jnxExVlanTag table, trying dot1qVlanStaticTable");
  #   my %dot1qVlanStaticEgressPorts;
  #   my $status = SwitchUtils::GetSnmpTable($Session,
  #                                       'dot1qVlanStaticEgressPorts',
  #                                       $Constants::INTERFACE,
  #                                       \%dot1qVlanStaticEgressPorts);
  #   if ($status == $Constants::SUCCESS) {
  #     my $SwitchName = GetName $Switch;
  #     $logger->debug("$SwitchName: dot1qVlanStaticEgressPorts table successfully read...");
  #     SwitchUtils::DbgPrintHash('dot1qVlanStaticEgressPorts', \%dot1qVlanStaticEgressPorts);

      
  #     #############################################################################
  #     # This was cut-and-pasted, and needs to be merged with the identical calls found elsewhere

  #     #
  #     # Get the table that maps bridge interface numbers to ifEntry numbers.
  #     #
  #     my %BifNbrToIfNbr;
  #     # $localSession->debug(DEBUG_ALL);
  #     my $status = SwitchUtils::GetSnmpTable($Session, # SNMP session
  #                                            'dot1dBasePortIfIndex', # table name
  #                                            $Constants::INTERFACE,  # table type
  #                                            \%BifNbrToIfNbr);       # returned table contents
  #     # $localSession->debug(DEBUG_NONE);
  #     if ($status != $Constants::SUCCESS) {
  #       $logger->debug("returning, couldn't get dot1dBasePortIfIndex (BifNbrToIfNbr) table");
  #       return;
  #     }

  #     #  SwitchUtils::DbgPrintHash('BifNbrToIfNbr', \%BifNbrToIfNbr);
  #     #############################################################################

      
  #     foreach my $vlan (keys %dot1qVlanStaticEgressPorts) {
  
  #       #        $logger->debug("$SwitchName: vlan = \"$vlan\"");
  #       my $portList = $dot1qVlanStaticEgressPorts{$vlan};
  #       #        $logger->debug("$SwitchName: portList = \"$portList\"");
  #       my @ports = split ',', $portList;
  #       foreach my $port (@ports) {
  #         next if $port eq '';
  #         my $truePort = $BifNbrToIfNbr{$port};
  #         my $PortName = $$IfToIfNameRef{$truePort};
  #         if (defined $PortName) {
  #           $logger->debug("$SwitchName: vlan = \"$vlan\", port = \"$port\", truePort = \"$truePort\", PortName = \"$PortName\"");
  #           #     my $tmp = $vmVlan{$ifNbr};
  #           #     $logger->debug("$SwitchName: setting \$\$VlansRef{$PortName} to \$vmVlan{$ifNbr} = $tmp");
  #                $$VlansRef{$PortName} = $vlan;
  #         } else {
  #           $logger->debug("$SwitchName: for \$vlan = \"%vlan\", \$PortName is not defined, skipping");
  #         }
  #       }
  #     }
  #     $doneGettingTable = 1;
  #   }
  # }

  if (!$doneGettingTable) {
    $logger->debug("it doesn't support the Juniper MIB, proceeding without Port-to-VLAN information");
  }


# When I get around to fetching VLAN information from Juniper devices,
# I'll look in jnxExVlanTable, jnxExVlanInterfaceTable, and
# jnxExVlanPortGroupTable.  Or, the QBridge MIB?

#
# Perhaps of value is dot1qNumVlans.0, the number of VLANs on the
# switch.  GetPortToMac loops through all the VLANs on the switch.
# Are those contained in the Q-BRIDGE MIB?
#
# And the following also works, suggesting that maybe we can use the
# Q-BRIDGE MIB to access Ciscos as well as Foundry switches.
# snmpwalk -v 2c -c ncar-read ml-16c-c1-gs .1.3.6.1.2.1.17.7.1.1
#
# The mechanism for identifying the VLAN per port is bit maps, with
# bit set for each port that is in a VLAN.  So you get the bitmap for
# each VLAN, and loop through the bits to figure out which ports are
# in the VLAN.  So I should be able to extend GetPortToVlanTable - after
# trying the Cisco MIBs, it can access the Q-BRIDGE MIB.  Then it
# should try the Q-BRIDGE MIB first if it works for Ciscos and
# Foundrys.
#
  my $SwitchName = GetName $Switch;
  $logger->debug("testing a GET of the dot1qNumVlans");
  my $dot1qNumVlans;
  my $status = SwitchUtils::GetOneOidValue($Session,
                                        'dot1qNumVlans',
                                        \$dot1qNumVlans);
  if ($status) {
    $logger->debug("GET succeeded, dot1qNumVlans = $dot1qNumVlans on switch $SwitchName");
  } else {
    $logger->debug("GET failed, couldn't get dot1qNumVlans from switch $SwitchName");
  }


# Now try to get the table of native VLAN numbers.  Then for each port
# in the table, if the native VLAN is something other than 1, override
# the VLAN number that's already been set.
  my %vlanTrunkPortNativeVlan;
  $status = SwitchUtils::GetSnmpTable($Session,
                                      'vlanTrunkPortNativeVlan',
                                      $Constants::INTERFACE,
                                      \%vlanTrunkPortNativeVlan);
  if ($status == $Constants::SUCCESS) {
    my $NbrVlans = keys %vlanTrunkPortNativeVlan;
    $logger->debug("got $NbrVlans native VLAN numbers from vlanTrunkPortNativeVlan table");
    foreach my $ifNbr (keys %vlanTrunkPortNativeVlan) {
      if ($vlanTrunkPortNativeVlan{$ifNbr} != 1) {
        my $PortName = $$IfToIfNameRef{$ifNbr};
        $$VlansRef{$PortName} = $vlanTrunkPortNativeVlan{$ifNbr};
      }
    }
  }

  #  This block of code was an attempt to make SwitchMap work on
  #  switches that don't support Cisco MIBs.  Try the Foundry MIBs...
  #
  #  $logger->debug("it doesn't support the Cisco VTP MIB, trying the Foundry MIBs");
  #  my %snSwPortVlanId;
  #  my $status = SwitchUtils::GetSnmpTable($Session,
  #                                          'snSwPortVlanId',
  #                                          $Constants::PORT,
  #                                          \%snSwPortVlanId);
  #  if ($status == $Constant::SUCCESS) {
  ##    This "worked" - the status was "success" but there was simply no returned data.  I can't explain this.
  ##    If you back aff and walk .1.3.6.1.4.1.1991.1.1.3.3, you get all the tables, including snSwPortVlanId.
  ##    Why is SNMP behaving this way?  I gave up and went after the Q-bridge MIB instead...
  #    if (%snSwPortVlanId) {
  #      $logger->fatal("got VLAN data from Foundry MIB, but code to interpret it hasn't been written yet");
  #      exit;
  #      $logger->debug("returning");
  #      return;
  #    } else {
  #      $logger->debug("Got SUCCESS from SNMP function call, but no returned data.");
  #    }
  #  }
  #
  #  If we made it to here, the switch doesn't support either Cisco or
  #  Foundry MIBs.  Try the standard Q-Bridge MIB.  (??????????)  What
  #  if it supports the MIB but is configured to use ISL trunking?
  #
  # $logger->debug("it doesn't support the Foundry MIBs, trying the standard Q-Bridge MIB");
  # my %TmpVlans;
  # GetMacsFromQBridgeMib::GetPortToVlanTableFromQBridgeMib($Switch, $Session, $IfToIfNameRef, \%TmpVlans);
  # if (%TmpVlans) {
  #   foreach my $vlan (sort keys %TmpVlans) {
  #     $logger->debug("-------------TmpVlans{$vlan} = \"$TmpVlans{$vlan}\"");
  #     $logger->fatal("got VLAN data from Q-bridge MIB, but code to interpret it hasn't been written yet");
  #     exit;
  #     $logger->debug("returning");
  #     return;
  #   }
  # }

  $logger->debug("returning");
}

1;

