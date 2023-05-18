package GetChassisModel;

use strict;
use Log::Log4perl qw(get_logger);
#use Data::Dumper;


sub GetChassisModelFromCiscoStackMib($$$) {
  my $this            = shift;
  my $Session         = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $cName = '';
  my $status = SwitchUtils::GetOneOidValue($Session,
                                           'chassisModel',
                                           \$cName);
  if ($status == $Constants::SUCCESS) {
    $this->{HasStackMIB} = $Constants::TRUE;
    if ($cName eq '') {
      $$chassisModelRef = $this->{ProductName};
    } else {
      $$chassisModelRef = 'Cisco ' . $cName;
    }
  } else {
    $this->{HasStackMIB} = $Constants::FALSE;
  }

  $logger->debug("returning");
}

sub GetChassisModelFromMikrotikMib($$) {
  my $Session         = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $cName = '';
  my $status = SwitchUtils::GetOneOidValue($Session,
                                           'sysDescr',
                                           \$cName);
  if ($status == $Constants::SUCCESS) {
    $cName =~ s/RouterOS //;
    $$chassisModelRef = 'Mikrotik ' . $cName;
  }

  $logger->debug("returning");
}


sub GetChassisModelFromEntityMib($$$) {
  my $Session         = shift;
  my $sysObjectId     = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my %entPhysicalClasses;
  my $status = SwitchUtils::GetSnmpTable($Session,
                                         'entPhysicalClass',
                                         $Constants::INTERFACE,
                                         \%entPhysicalClasses);
  if ($status == $Constants::SUCCESS) {
    $logger->debug("got the entPhysicalClass table, finding the chassis");
#    SwitchUtils::DbgPrintHash('entPhysicalClass', \%entPhysicalClasses);
    my $chassisIndex = -1;
    foreach my $indx (%entPhysicalClasses) {
      if (exists $entPhysicalClasses{$indx} and ($entPhysicalClasses{$indx} == $Constants::CHASSIS)) {
        $chassisIndex = $indx;
      }
    }
    if ($chassisIndex != -1) {  # if we found a chassis entity
      $logger->debug("the index of the chassis item in entPhysicalClasses is \"$chassisIndex\"");
      $logger->debug("getting the entPhysicalModelName table...");
      my %entPhysicalModelNames;
      $status = SwitchUtils::GetSnmpTable($Session,
                                          'entPhysicalModelName',
                                          $Constants::INTERFACE,
                                          \%entPhysicalModelNames);
      if ($status == $Constants::SUCCESS) {
#        SwitchUtils::DbgPrintHash('entPhysicalModelName', \%entPhysicalModelNames);
        my $physicalModelName = $entPhysicalModelNames{$chassisIndex};
        $physicalModelName =~ s/^CISCO//;
        $physicalModelName =~ s/ +$//; # trim trailing spaces
        my $vendor = '';
        if ($sysObjectId =~ /^1\.3\.6\.1\.4\.1\.2636\./) {
          $vendor = 'Juniper';
        } elsif ($sysObjectId =~ /^1\.3\.6\.1\.4\.1\.9\./) {
          $vendor = 'Cisco';
        } elsif ($sysObjectId =~ /^1\.3\.6\.1\.4\.1\.1991\./) {
          $vendor = 'Brocade';
        } elsif ($sysObjectId =~ /^1\.3\.6\.1\.4\.1\.14988\./) {
          $vendor = 'Mikrotik';
        }
        $$chassisModelRef = $vendor . ' ' . $physicalModelName;
        $logger->debug("got entPhysicalModelNames, setting chassisModelRef to $$chassisModelRef");
      }
    }
  }
  $logger->debug("returning");
}


sub GetChassisModelFromCiscoProductsMib($$) {
  my $sysObjectId     = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $cName = CiscoMibConstants::getCiscoChassisName($sysObjectId);
  if ($cName ne '') {
    $cName =~ s/^catalyst//;
    $cName =~ s/^cisco//;
    $cName =~ s/^ciscoPro//;
    $cName =~ s/^ciscosysID//;
    $cName =~ s/^wsc//;
    $cName =~ s/sysID$//;
    $$chassisModelRef = 'Cisco ' . $cName;
  }

  $logger->debug("returning");
}


sub GetChassisModelFromHpProductsMib($$) {
  my $sysObjectId     = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $cName = HpMibConstants::getHpDeviceName($sysObjectId);
  if ($cName ne '') {
    $$chassisModelRef = $cName;
  }

  $logger->debug("returning");
}


sub GetChassisModelFromJuniperSysDescr($$) {
  my $sysDescr        = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called, sysDescr = \"$sysDescr\"");

  if ($sysDescr =~ /^Juniper Networks, Inc. ([^ ]+)/) {
    $$chassisModelRef = 'Juniper ' . $1;
  }

  $logger->debug("returning");
}


sub GetChassisModelFromBrocadeSysDescr($$) {
  my $sysDescr        = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called, sysDescr = \"$sysDescr\"");

  if ($sysDescr =~ /^Brocade /) {
    my $remainder = $';
    $remainder =~ s/^Communication Systems, Inc\. //;
    $remainder =~ /^([^ ,]+)/;
    $$chassisModelRef = 'Brocade ' . $1;
  }

  $logger->debug("returning");
}


sub GetChassisModelFromFoundryMib($$) {
  my $sysObjectId     = shift;
  my $chassisModelRef = shift;
  my $logger = get_logger('log4');
  $logger->debug("called, sysObjectId = \"$sysObjectId\"");
  if (exists $Constants::FoundrySwitchObjectOids{$sysObjectId}) {
    $$chassisModelRef = $Constants::FoundrySwitchObjectOids{$sysObjectId};
  }
  $logger->debug("returning");
}


#
# Find out what type of switch it is.
#
sub GetChassisModel ($$) {
  my $Switch  = shift;
  my $Session = shift;
  my $logger = get_logger('log3');
  $logger->debug("called");

  my $chassisModel = 'unknown';
  GetChassisModelFromCiscoStackMib($Switch, $Session, \$chassisModel);
  if ($chassisModel eq 'unknown') {
    # The switch didn't respond, so either it's unreachable, or it's
    # slow, or it doesn't support the Cisco Stack MIB.  Assume that it
    # doesn't support the Cisco Stack MIB, and try the Entity MIB.
    $logger->info("couldn't get it from the Cisco Stack MIB, trying the Entity MIB...");
    GetChassisModelFromEntityMib($Session, $Switch->{SnmpSysObjectId}, \$chassisModel);
  }
  if ($chassisModel =~ /^Mikrotik/) {
    GetChassisModelFromMikrotikMib($Session, \$chassisModel);
  }
  if ($chassisModel eq 'unknown') {
    # It doesn't support either the Cisco Stack MIB or the Entity MIB.
    # Some Cisco 3524s are like this, as are non-Cisco switches like
    # Foundry switches.  Try using the sysOBjectID to look up the
    # chassis model in the Cisco Products MIB.
    $logger->info("couldn't get it from the Entity MIB, use the sysObjectID to look it up in the Cisco STACK and PRODUCTS lists...");
    GetChassisModelFromCiscoProductsMib($Switch->{SnmpSysObjectId}, \$chassisModel);
  }
  if ($chassisModel eq 'unknown') {
    # It must not be a Cisco device.  Try HP.
    $logger->info("couldn't get it from the Cisco Products MIB, trying HP...");
    GetChassisModelFromHpProductsMib($Switch->{SnmpSysObjectId}, \$chassisModel);
  }
  if ($chassisModel eq 'unknown') {
    # It must not be an HP device.  Assume it's a Juniper and try
    # parsing the model number out of the sysDecription.
    $logger->info("couldn't get it from the Cisco Products MIB, use the sysObjectID to parse it out of the Juniper sysDescr...");
    GetChassisModelFromJuniperSysDescr($Switch->{SnmpSysDescr}, \$chassisModel);
  }
  if ($chassisModel eq 'unknown') {
    # It must not be a Juniper device.  Assume it's a Brocade and try
    # parsing the model number out of the sysDecription.
   $logger->info("couldn't get a Juniper model, trying parsing a Brocade model string out of the sysDecription...");
    GetChassisModelFromBrocadeSysDescr($Switch->{SnmpSysDescr}, \$chassisModel);
  }
  if ($chassisModel eq 'unknown') {
   # Brocade bought Foundry in 2008.  Many "Foundry" switches have
   # sysDescr strings that start with "Brocade...", so they are
   # matched by GetChassisModelFromBrocadeSysDescr.  This next test
   # is meant to match really old (before Brocade bought Foundry)
   # Foundry switches.
   $logger->info("couldn't get a Brocade model, use the sysObjectID to look it up in the Foundry MIB...");
    GetChassisModelFromFoundryMib($Switch->{SnmpSysObjectId}, \$chassisModel);
  }
  if ($chassisModel eq 'unknown') {
    my $SwitchName = $Switch->{Name};
    $logger->warn("for switch $SwitchName, couldn't figure out the model, leaving it \'unknown\'");
  } else {
    $Switch->{ChassisModel} = $chassisModel;
  }
  $logger->debug("returning success, type is \"$chassisModel\"");
  return $Constants::SUCCESS;
}
1;
