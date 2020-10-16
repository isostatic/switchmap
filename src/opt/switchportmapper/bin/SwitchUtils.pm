#
#   SwitchUtils.pm - part of SwitchMap
#
#--------------------------------------------------------------------------
# Copyright 2010 University Corporation for Atmospheric Research
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
# 02111-1307, USA.
#
# For more information, please contact
# Pete Siemsen, siemsen@ucar.edu
#--------------------------------------------------------------------------
#
#
# This file is intended to be included in other Perl scripts.  See the
# scanswitch.pl script for more information.
#

package SwitchUtils;

use strict;
use Log::Log4perl qw(get_logger);
use Portically;
#use Data::Dumper;
use OuiCodes;
use ThisSite;

sub DbgPrintHash ($$) {
  my $hashname = shift;
  my $hash = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $keycount = keys %{$hash};
  if ($keycount == 0) {
    $logger->debug("$hashname is empty");
  } else {
    foreach (Portically::PortSort keys %{$hash}) {
      $logger->debug("$hashname\{$_\} = \"$$hash{$_}\"");
    }
  }
  $logger->debug("returning");
}


#
# The following two subroutines are called by ScanSwitch,
# PopulatePorts (via SwitchMap) and SetDaysInactiveForm (via
# a web form).  The first two use logging to report errors,
# but SetDaysInactiveForm has to use HTML output.  These
# two ways of reporting errors are incompatiple, so these
# subroutines can't directly use either.  Instead, both
# subroutines return a string representing the status of
# the call, and let the caller report the status using
# the caller's style.  If the status string is empty, the
# call was successful.  Otherwise the string contains an
# error message.
#
sub ReadIdleSinceFile ($$) {
  my $IdleSinceFile = shift;
  my $IdleSinceRef  = shift;

  open IDLESINCEFILE, $IdleSinceFile or do {
    return "Couldn't open $IdleSinceFile for reading, $!\n";
  };
  while (<IDLESINCEFILE>) {
    chop;
    next if /^#/;
    my $LastSpace = rindex $_, ' ';
    my $PortName = substr $_, 0, $LastSpace;
    my $Time = substr $_, $LastSpace+1;
    next if $Time !~ /^\d+$/; # skip possible old ill-formed entries from versions of SwitchMap before 11.0
    $$IdleSinceRef{$PortName} = $Time;
  }
  close IDLESINCEFILE;
  return "";
}


sub AllowOnlyOwnerToReadFile ($) {
  my $FileName = shift;
  chmod 0600, $FileName;      # 0600 = "-rw-------", owner read/write
}


sub AllowAllToReadFile ($) {
  my $FileName = shift;
  chmod 0664, $FileName;      # 0664 = "-rw-rw-r--", owner read/write
}


#
# See the above comment for ReadIdleSinceFile - it also applies to
# this subroutine.
#
sub WriteIdleSinceFile ($$) {
  my $IdleSinceFile = shift;
  my $IdleSinceRef  = shift;
#  WARNING: don't uncomment these for production - they'll cause SetDaysInactive.pl to emit
#       "Log4perl: Seems like no initialization happened. Forgot to call init()?"
#  which is illegal HTML.
#  my $logger = get_logger('log2');
#  $logger->debug("called");

  open IDLESINCEFILE, ">$IdleSinceFile" or do {
    return "Couldn't open $IdleSinceFile for writing, $!\n";
  };
  print IDLESINCEFILE <<IHEADER;
# This file maintains state information about Cisco switch ports.
# It was generated by the ScanSwitch.pl Perl script, and is read by
# the SwitchMap.pl Perl script.  Do not edit this file.
#
# Each line contains a port name, a space, and a Unix-format timestamp
# of the time that the port was last detected active.  A timestamp of
# 0 means the port was active the last time it was checked.
IHEADER
  foreach my $PortName (keys %{$IdleSinceRef}) {
    print IDLESINCEFILE "$PortName $$IdleSinceRef{$PortName}\n";
  }
  close IDLESINCEFILE;
  AllowAllToReadFile $IdleSinceFile;
#  $logger->debug("returning, wrote $IdleSinceFile");
  return "";
}


#
# Get a single OID from a device.  Return true if there were no
# errors.
#
sub GetOneOidValue ($$$) {
  my $Session   = shift;
  my $ValueName = shift;
  my $retref    = shift;
  my $logger    = get_logger('log4');

  my $DeviceName = $Session->hostname();
  $logger->debug("called to fetch $ValueName from $DeviceName");

  if (!exists $Constants::SnmpOids{$ValueName}) {
    $logger->fatal("Internal error: Unknown SNMP OID $ValueName");
    exit;
  }
  my $ValueOid = $Constants::SnmpOids{$ValueName};

  my $result = $Session->get_request(-varbindlist => [$ValueOid]);

  if (!(defined $result) or
      ($result->{$ValueOid} eq 'noSuchObject') or
      ($result->{$ValueOid} eq 'noSuchInstance')) {
    $logger->debug("returning FAILURE");
    return $Constants::FAILURE;
  }

  $$retref = $result->{$ValueOid};
  $logger->debug('returning "' . $$retref . '"');
  return $Constants::SUCCESS;
}


#
# When we get an SNMP table, each row comes back with 2 values:
# one imbebbed in the returned OID and one real value.  The value
# embedded in the OID can be
#   just the last octet (in the case of interface tables) or
#   the last two octets (in the case of ports or etherchannel parent/child relationships) or
#   the last 4 octets (in the case of IP addresses).
# This subroutine is passed the table type and an OID, and
# returns the value embedded in the OID.
#
sub GetOidValue ($$) {
  my $TableType = shift;        # INTERFACE, PORT or IP_ADDRESS
  my $Oid = shift;
  my $logger = get_logger('log5');

  my $RetVal = '';
  my $pattern = $Constants::OidPatterns[$TableType];
  $Oid =~ /$pattern/;
  if ((defined $1) and ($1 ne '')) {
    $RetVal = trim($1);
    if ($TableType == $Constants::PORT) {
      $RetVal =~ s/\./\//;      # replace the period with a slash
    } elsif ($TableType == $Constants::MAC_ADDRESS) {
      $RetVal = sprintf '%02x%02x%02x%02x%02x%02x', split(/\./, $RetVal);
    }
  }
  # $logger->debug("returning \"$RetVal\"");
  return $RetVal;
}


sub GetSnmpTable ($$$$) {
  my $Session       = shift;
  my $TableName     = shift;
  my $TableType     = shift;
  my $ReturnedTable = shift;
  my $logger = get_logger('log7');
  $logger->debug("called, getting $TableName table...");

  my $functionTimer = new Timer "in getSnmpTable, getting $TableName", $Timer::MINOR_FUNCTION;
  $functionTimer->start;

  my $TableOid;
  if (!exists $Constants::SnmpOids{$TableName}) {
    $logger->fatal("Unknown SNMP OID $TableName");
    exit;
  }
  $TableOid = $Constants::SnmpOids{$TableName};

  my $Table = $Session->get_table($TableOid);
  if (!defined $Table) {
    $logger->debug("Couldn't get $TableName table: " . $Session->error() .
                   ", SNMP error status: " . $Session->error_status() .
                   ", SNMP error index: " . $Session->error_index);
    $functionTimer->stop;
    $logger->debug("returning failure");
    return $Constants::FAILURE;
  }

  # If there's only only one value, and it consists of 'endOfMibView' (Brocade switches do this),
  # then it's the same as returning nothing, and we explicitly return nothing.
  my $count = keys %{$Table};
  if ($count == 1) {
    my @Oids = keys %{$Table};
    my $onlyOid = $Oids[0];
    if ($Table->{$onlyOid} eq 'endOfMibView') {
      $logger->debug("returning failure because got \"endOfMibView\"");
      $functionTimer->stop;
      return $Constants::FAILURE;
    }
  }

  foreach my $Oid (keys %{$Table}) {
    my $OidValue = GetOidValue $TableType, $Oid;
    if ($OidValue eq '') {
      $logger->warn("couldn't extract SNMP value from row in table $TableName with OID=$TableOid, row was $Oid");
    } else {
      # my $t1 = $Table->{$Oid};
      # $logger->debug("Oid = \"$Oid\",\tOidValue = \"$OidValue\",\tTable{$OidValue} = \"$t1\"");
      $$ReturnedTable{$OidValue} = $Table->{$Oid};
    }
  }

  $functionTimer->stop;

  $logger->debug("returning hash with $count values");
  return $Constants::SUCCESS;
}


sub GetSnmpv3VlanTable {
  my ($Session, $TableName, $TableType, $ReturnedTable, $VlanNumber) = @_;
  my $logger = get_logger('log8');
  $logger->debug("called, getting $TableName table...");

  my $TableOid;

  # Formulate the Context Name from the VLAN number, as described in
  # https://supportforums.cisco.com/discussion/10056071/snmpv3-community-string-indexing
  my $SNMPv3ContextName = sprintf("vlan-%s", $VlanNumber);

  if (!exists $Constants::SnmpOids{$TableName}) {
    $logger->fatal("Unknown SNMP OID $TableName");
    exit;
  }
  $TableOid = $Constants::SnmpOids{$TableName};

  my $Table = $Session->get_table(
                                  -baseoid  => $TableOid,
                                  -contextname => $SNMPv3ContextName);
  if (!defined $Table) {
    $logger->debug("Couldn't get $TableName table: " . $Session->error() .
                   ", SNMP error status: " . $Session->error_status() .
                   ", SNMP error index: " . $Session->error_index);
    $logger->debug("returning failure");
    return $Constants::FAILURE;
  }

  # If there's only only one value, and it consists of 'endOfMibView' (Brocade switches do this),
  # then it's the same as returning nothing, and we explicitly return nothing.
  my $count = keys %{$Table};
  if ($count == 1) {
    my @Oids = keys %{$Table};
    my $onlyOid = $Oids[0];
    if ($Table->{$onlyOid} eq 'endOfMibView') {
      $logger->debug("GetSnmpv3VlanTable: returning failure because got \"endOfMibView\"");
      return $Constants::FAILURE;
    }
  }

  foreach my $Oid (keys %{$Table}) {
    my $OidValue = GetOidValue $TableType, $Oid;
    if ($OidValue eq '') {
      $logger->warn("couldn't extract SNMP value from row in table $TableName with OID=$TableOid, row was $Oid");
    } else {
      # my $t1 = $Table->{$Oid};
      # $logger->debug("Oid = \"$Oid\",\tOidValue = \"$OidValue\",\tTable{$OidValue} = \"$t1\"");
      $$ReturnedTable{$OidValue} = $Table->{$Oid};
    }
  }

  $logger->debug("returning hash with $count values");
  return $Constants::SUCCESS;
}


#
# Get the name mapping tables - the tables that map interface numbers
# to names and vice versa.  For Catalysts, the IfToIfName table maps,
# like, SNMP MIB-II interface number "12" to name "3/2".  Besides the
# regular interfaces, the table can have some funny "interfaces" in it
# with names like GEC-1, ATM2/0, LEC/ATM2/0.24, VLAN-74, etc.
#
sub GetNameTables ($$$) {
  my $Session       = shift;   # passed in
  my $IfToIfNameRef = shift;   # filled by this function, maps interface numbers to interface names
  my $IfNameToIfRef = shift;   # filled by this function, maps interface names to interface numbers
  my $logger = get_logger('log5');
  $logger->debug("called");

  $logger->info("getting interface-to-name tables");
  my %ifName;
  my $status = GetSnmpTable($Session,
                            'ifName',
                            $Constants::INTERFACE,
                            \%ifName);
  if ($status != $Constants::SUCCESS) {
    $logger->debug("returning failure");
    return $Constants::FAILURE;
  }

  foreach my $IfNbr (keys %ifName) {
    my $InterfaceName = $ifName{$IfNbr};
    $InterfaceName =~ s/ +$//;    # remove trailing spaces (1912C switches have these)
    $$IfToIfNameRef{$IfNbr} = $InterfaceName;
    $$IfNameToIfRef{$InterfaceName} = $IfNbr;
  }

  # DbgPrintHash('IfNameToIfRef', $IfNameToIfRef);
  my $NbrNames = keys %ifName;
  $logger->debug("returning, got $NbrNames interface names");
  return $Constants::SUCCESS;
}


#
# Open an SNMP session with a switch using Net::SNMP.
# Try multiple SNMP community strings if we have them.
# Return a success or failure boolean.
# If success, return the session object and the community
# string that was used to open the session.
#
sub OpenSnmpSession ($$$$) {
  my $DeviceName       = shift; # passed in
  my $GoodsessionRef   = shift; # returned
  my $GoodCommunityRef = shift; # returned
  my $SysObjectIdRef   = shift; # returned
  my $logger = get_logger('log3');
  my $logger4 = get_logger('log4');
  $logger->debug("called to open a session to $DeviceName");

  my $Community = "";
  my $snmp_version = $ThisSite::SNMP_version;
  my $Session;
  my $Error;

  $logger4->debug("trying to open an SNMP session to $DeviceName");
  if (int($snmp_version) == 2) {
    foreach my $Community (SnmpCommunities::GetCommunities($DeviceName)) {
      $logger4->debug("trying community = \"$Community\"");

      # Use the -translate argument to prevent the Net::SNMP code from
      # automatically converting unprintable returned SNMP values into
      # human-readable form.  It doesn't correctly translate MAC addresses
      # that contain unprintable characters.  We'll do the translation
      # ourselves.  It seems that I can use the Net::SNMP "translate"
      # call to change the setting for the session on-the-fly.  I should
      # probably use that capability to turn translation off only when
      # I'm reading MAC addresses.  For now, just turn it off for all
      # GETs.

      ($Session, $Error) = Net::SNMP->session(
                                              -version    => 'snmpv2c',
                                              -timeout    => 5,
                                              -hostname   => $DeviceName,
                                              -community  => $Community,
                                              -translate  => [-octetstring => 0x0]
                                             );

      if ($Session) {
        $logger4->debug("SNMPv2 session open, testing a GET of the sysObjectId");
        my $sysObjectID;

        my $status = GetOneOidValue($Session,
                                    'sysObjectID',
                                    \$sysObjectID);

        if ($status) {
          $logger4->debug("SNMPv2 GET succeeded, valid SNMP session opened");
          $$GoodCommunityRef = $Community;
          $$GoodsessionRef = $Session;
          $$SysObjectIdRef = $sysObjectID;
          SnmpCommunities::WriteCommunityToCacheFile($DeviceName, $Community);
          $logger->debug("returning SUCCESS, sysObjectID = $sysObjectID");
          return $Constants::SUCCESS;
        } else {
          $logger4->debug("SNMPv2 GET failed, probably because the device doesn't recognize the SNMP community string");
          $Session->close ();
        }
      } else {
        $logger->error("couldn't open SNMPv2 SNMP session to $DeviceName: $Error");
      }
    }
  } else {
    my $secName      = $ThisSite::SNMPv3_secName;
    my $privProtocol = $ThisSite::SNMPv3_privProtocol;
    my $privPassword = $ThisSite::SNMPv3_privPassword;
    my $authProtocol = $ThisSite::SNMPv3_authProtocol;
    my $authPassword = $ThisSite::SNMPv3_authPassword;
    ($Session, $Error) = Net::SNMP->session(
                                            -version      => 'snmpv3',
                                            -username     => $secName,
                                            -authprotocol => $authProtocol,
                                            -authpassword => $authPassword,
                                            -privprotocol => $privProtocol,
                                            -privpassword => $privPassword,
                                            -timeout      => 5,
                                            -hostname     => $DeviceName,
                                            -maxmsgsize   => 5000,
                                            -translate    => [-octetstring => 0x0]
                                           );

    if ($Session) {
      $logger4->debug("SNMPv3 session open, testing a GET of the sysObjectId");
      my $sysObjectID;
      my $status = GetOneOidValue($Session,
                                  'sysObjectID',
                                  \$sysObjectID);

      if ($status) {
        $logger4->debug("SNMPv3 GET succeeded, valid SNMP session opened");
        $$GoodCommunityRef = $Community;
        $$GoodsessionRef = $Session;
        $$SysObjectIdRef = $sysObjectID;
        $logger->debug("returning SUCCESS, sysObjectID = $sysObjectID");
        return $Constants::SUCCESS;
      } else {
        $logger4->debug("SNMPv3 GET failed, probably because the device doesn't recognize the SNMP community string");
        $Session->close ();
      }
    } else {
      $logger->error("couldn't open SNMPv3 SNMP session to $DeviceName: $Error");
    }
  }

  $logger->debug("returning");
  return $Constants::FAILURE;
}


#
# Return a hash of bit fields, one for each VLAN on the switch.
#
# sub GetVlanBitFields ($$) {
#   my $Session = shift;
#   my $oid = shift;
#   my $logger = get_logger('log5');
#   $logger->debug("called");

#   my %ReturnedHash;
#   my $toid = 'dot1qVlanCurrentEgressPorts';
#   # maybe get_table isn't the right call.  See usr/local/share/perl/5.8.4/Net/SNMP.pm
#   my $PortBitFields = $Session->get_table($Constants::SnmpOids{$toid});
#   if (defined($PortBitFields)) {
#     foreach my $ReturnedOid (keys %{$PortBitFields}) {
#       $logger->debug("ReturnedOid = \"$ReturnedOid\"");
#       # When you get dot1qVlanCurrentEgressPorts, you expect to get
#       # back 1 bitfield for each VLAN, but you actually get back
#       # several bitfields for each VLAN.  Each of the bitfields comes
#       # back with an OID that's unique.  Each OID is
#       # dot1qVlanCurrentEgressPorts with two octets appended to the
#       # end.  The last octet is the VLAN number.  The second-to-last
#       # octet is some other weird number that's unique.  I don't know
#       # what the number represents, but I noticed that in the set of
#       # returned OIDs, only one of them has a zero in the
#       # second-to-last octet.  I chose to save that one and ignore
#       # the others.
#       $ReturnedOid =~ /(\d+)\.(\d+)$/;
#       my $WeirdNumber = $1;
#       if ($WeirdNumber == '0') {
#         my $Vlan = $2;
#         $logger->debug("Vlan = \"$Vlan\"");
#         $ReturnedHash{$Vlan} = $$PortBitFields{$ReturnedOid};
#       }
#     }
#   } else {
#     my $hostname = $Session->hostname;
#     my $tmp = $Session->error();
#     # this isn't right!! - handle this error more gracefully
#     $logger->debug("couldn't get $toid from $hostname, $tmp");
#   }

#   $logger->debug("returning");
#   return %ReturnedHash;
# }


#
# Return the current date/time in ISO 8601 format.
#
sub TimeStr () {
  my ($sec,$min,$hour,$mday,$mon,$year) = localtime time;
  $mon++;
  $year += 1900;
  return sprintf "%s-%02s-%02s at %02s:%02s:%02s", $year, $mon, $mday, $hour, $min, $sec;
}


#
# Some Cisco switches report odd ports, like 'Nu0' (the null port),
# that aren't worth showing in the SwitchMap output, and that
# shouldn't be shown in the NCAR Call Manager CSV file.  This function
# checks for these ports.  It simply returns true if the given string
# matches one of the patterns of known odd ports.
#
sub IsAncillaryPort ($) {
  my $Port = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $RetVal = $Constants::FALSE;
  my $PortType = (defined $Port->{Type}) ? $Port->{Type} : 0;
  if ($PortType == 1) {       # 1 = other
      $RetVal = $Constants::TRUE;
  } else {
    my $PortName = $Port->{Name};
    if (($PortName =~ /^As\d+/)          or # Async "ports"
        ($PortName =~ /^CPU/)            or # CPU "ports" on 1912C switches
        ($PortName =~ /^Di\d+/)          or # Dialer "ports"
        ($PortName =~ /^FEC-/)           or # Fast-Ethernet Etherchannel virtual ports
        ($PortName =~ /^GEC-/)           or # skip Gigabit Etherchannel virtual ports
        ($PortName =~ /^Nu\d+/)          or # null ports
        ($PortName =~ /^VLAN-/)          or # VLAN "ports"
        ($PortName =~ /^VL\d+/)          or # weird 3524 "ports"
        ($PortName =~ /^Vl\d+/)          or # VLAN on 3750
        ($PortName =~ /^s(l|c)(0|1)/)    or # console ports
        ($PortName =~ /^sup-fc\d+/)      or # Nexus Fiber Channel ports
        ($PortName =~ /--Controlled$/)   or # IEEE 802.1X thing, look up the Cisco "authentication control-direction"...
        ($PortName =~ /--Uncontrolled$/) or # command for details
        ($PortName eq 'inband')) {        # inband port, on which the switch does its internal
                                          # communication.  The supervisor and the blades on the switch use
                                          # the "inband" port for hello packets and STP traffic between the
                                          # cards.
      $RetVal = $Constants::TRUE;
    }
  }

  $logger->debug("returning $RetVal");
  return $RetVal;
}


sub NavigationBar () {

my $RootPath        = $ThisSite::DestinationDirectoryRoot . '/' . 'index.html';
my $SwitchesPath    = $ThisSite::DestinationDirectoryRoot . '/' . 'switches/index.html';
my $ModulesPath     = $ThisSite::DestinationDirectoryRoot . '/' . $Constants::ModulesBySwitchFile;
my $PortsPath       = $ThisSite::DestinationDirectoryRoot . '/' . 'ports/index.html';
my $VlansPath       = $ThisSite::DestinationDirectoryRoot . '/' . 'vlans/index.html';
my $SearchPLPath    = $ThisSite::DestinationDirectoryRoot . '/' . 'SearchPortlists.html';
my $Statistics      = $ThisSite::DestinationDirectoryRoot . '/' . $Constants::SwitchStatsFile;

return <<NAVIGATIONBAR;

<ul class="toc">
     <li><a href="$RootPath">Home</a></li>
     <li><a href="$SwitchesPath">Switches</a></li>
     <li><a href="$ModulesPath">Modules</a></li>
     <li><a href="$PortsPath">Ports</a></li>
     <li><a href="$VlansPath">VLANs</a></li>
     <li><a href="$SearchPLPath">Search&nbsp;port&nbsp;lists</a></li>
     <li><a href="$Statistics">Statistics</a></li>
   </ul>
   <br>
NAVIGATIONBAR
}


sub HtmlHeader ($) {
my $title = shift;

my $CssFilePath = $ThisSite::DestinationDirectoryRoot . '/' .$Constants::CssFile;
my $NavBar      = NavigationBar();

my $RetVal = <<HEAD;
<!doctype html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta name="ROBOTS" content="NOINDEX, NOFOLLOW">
<meta Http-Equiv="Pragma" Content="no-cache">
<meta Http-Equiv="Expires" Content="-100">
<title>$title</title>
<link href="$CssFilePath" rel="stylesheet" type="text/css">
</head>
<body>

$NavBar
<div class="page-title">$title</div>

HEAD
return $RetVal;
}


sub HtmlTrailer {
  my $timstr = TimeStr;
  my $url = 'http://sourceforge.net/projects/switchmap/';
  my $MyName = PetesUtils::ThisScriptName();
  my $RetVal = <<TRAIL;
<hr>
<div class="trailer">
This web page was generated by the "$MyName" program (version $Constants::VERSION) on $timstr.<br>
The program is available at
<a href="$url">
$url</a>
$ThisSite::WebPageTrailer
</div>
</body>
</html>
TRAIL
  return $RetVal;
}


sub HtmlPortTableHeader () {
  return <<HPTH;
<table border class="Port" summary=\"Port information\">
<caption><strong>Port information</strong></caption>
<tr class = "tblHead">
<th colspan="7">information about the port itself</th>
<th colspan="6">information about what the port is connected to</th>
</tr>
<tr class="tblHead">
<th>Port</th>
<th>VLAN</th>
<th>State</th>
<th>Days<br>Inactive</th>
<th>Speed</th>
<th>Duplex</th>
<th>Port Label</th>
<th>CDP</th>
<th>LLDP</th>
<th>MAC Address</th>
<th>NIC<br>Manufacturer</th>
<th>IP Address</th>
<th>DNS Name</th>
</tr>
<tr><td colspan="13" height="2" bgcolor="black"></td></tr>
HPTH
}


sub GetVlanNbr ($$) {
  my $Port = shift;
  my $DepthBelowDestinationDirectory = shift;
  my $logger = get_logger('log5');
  $logger->debug("called, DepthBelowDestinationDirectory = $DepthBelowDestinationDirectory");

  my $VlanNbr = 'n/a';

  if (exists $Port->{VlanNbr}) {
    if (defined $Port->{VlanNbr}) {
      $VlanNbr = $Port->{VlanNbr};
      # If the VLAN file is accessible with a relative path, make a link to the VLAN file.
      # It'll be accessible with a relative path if we were called from SwitchMap, but not if we were called from FindOffice.pl.
      my $VlanFileName = 'vlan' . $VlanNbr . '.html';
      if (-r File::Spec->catfile($Constants::VlansDirectory, $VlanFileName)) {
        my $RelativePath = File::Spec->catfile('vlans', $VlanFileName);
        for (my $i=0; $i<$DepthBelowDestinationDirectory; $i++) {
          $RelativePath = File::Spec->catfile('..', $RelativePath);
        }
        $VlanNbr = '<a href="' . $RelativePath . '">' . $VlanNbr . '</a>';
      }
    }
  }
  $logger->debug("returning \"$VlanNbr\"");
  return $VlanNbr;
}


sub GetRowColor ($$) {
  my $State        = shift;
  my $DaysInactive = shift;

  my $RowColor;
  if ($State eq 'Active') {
    $RowColor = "cellActive";
  } else {
    if (($DaysInactive ne '&nbsp;') and ($DaysInactive ne 'unknown') and ($DaysInactive > $ThisSite::UnusedAfter)) {
      $RowColor = "cellUnused";
    } else {
      $RowColor = "cellDefault";
    }
  }
  return $RowColor;
}


sub GetWhatViaCdp ($$) {
  my $Port                           = shift;
  my $DepthBelowDestinationDirectory = shift;
  my $logger = get_logger('log5');
  $logger->debug("called");

  my $WhatViaCdp = '&nbsp;';
  if ($Port->{CdpCachePlatform} ne '') {
    $WhatViaCdp = '<nobr>' . $Port->{CdpCachePlatform} . '</nobr>';
    if ($Port->{CdpCacheDeviceId} ne '') {
      my $cdpDeviceId = $Port->{CdpCacheDeviceId};
      $WhatViaCdp .= '<br>';
      $WhatViaCdp =~ s/\n/\/\//g; # change embedded newlines to //
      $WhatViaCdp =~ s/\r/\/\//g; # change embedded carriage returns to //
      if (($cdpDeviceId =~ /\(([A-Za-z0-9-]+)/) or      # if it's, like, TBA05290738(ml-243b-c1-gs.ucar.edu), get the "ml-243b-c1-gs"
          ($cdpDeviceId =~ /^([A-Za-z0-9-]+)\./)) {     #    it's, like, mlra.ucar.edu, we want the "mlra"
        my $cdpDevice = $1;
        if (-r File::Spec->catfile($Constants::IdleSinceDirectory, $cdpDevice . '.idlesince')) {
          my $RelativePath = File::Spec->catfile('switches', $cdpDevice . '.html');
          for (my $i=0; $i<$DepthBelowDestinationDirectory; $i++) {
            $RelativePath = File::Spec->catfile('..', $RelativePath);
          }
          $WhatViaCdp .= '<a href="' . $RelativePath . '">' . $cdpDevice . '</a>';
        } else {
          $WhatViaCdp .= $cdpDevice;
        }
      } else {
        if ($ThisSite::ShowCdpName) {
          $WhatViaCdp .= "$cdpDeviceId" if $cdpDeviceId !~ /^SEP/;  # skip it it's a Cisco IP phone serial number
        }
      }
    }
  }
  $logger->debug("returning");
  return $WhatViaCdp;
}

sub GetWhatViaLLDP ($) {
  my $Port = shift;
  my $logger = get_logger('log5');
  $logger->debug("called");

  my $WhatViaLLDP = '&nbsp;';
  if ($Port->{lldpRemSysName} ne '') {
    my $lldpRemSysName= $Port->{lldpRemSysName};
    $lldpRemSysName=~ s{^([^.]+\.[^.]*)\..*}{$1};
    $WhatViaLLDP= '<nobr>' . $lldpRemSysName . '</nobr>';
    if ($Port->{lldpRemPortDesc} ne '') {
      my $lldpRemPortDesc= $Port->{lldpRemPortDesc};
      $lldpRemPortDesc=~ s{^([A-Z][-A-Za-z])[-A-Za-z]+([0-9/]+)$}{$1$2}; # shorten IOS long names
      $WhatViaLLDP.= '<br>' . $lldpRemPortDesc;
    }
    $WhatViaLLDP.= ' '. $Port->{lldpRemManAddr} if ($Port->{lldpRemManAddr} ne '');
  }

  $logger->debug("returning");
  return $WhatViaLLDP;
}


sub GetPortLabel ($) {
  my $Port  = shift;

  my $PortLabel = '&nbsp;';
  if (defined $Port->{Label}) {
    if ($Port->{Label} ne '') {
      $PortLabel = $Port->{Label};
    }
  }
  return $PortLabel;
}


# Given a port, return the first half of the table row for the port.
# The first half is the "information about the port itself" part.
sub GetPortInfoCells ($$$) {
  my $Port                           = shift;
  my $RowSpan2                       = shift;
  my $DepthBelowDestinationDirectory = shift;
  my $logger = get_logger('log4');
  $logger->debug("called");

  my $PortName      = $Port->{Name};
  my $VlanNbr       = GetVlanNbr($Port, $DepthBelowDestinationDirectory);
  my $State         = $Port->{State};
  my $DaysInactive  = ($Port->{DaysInactive} ne '') ? $Port->{DaysInactive} : '&nbsp;';
  my $Speed         = (defined $Port->{Speed}) ? $Port->{Speed} : 'n/a';
  my $Duplex        = (exists $Port->{Duplex}) ? $Port->{Duplex} : 'n/a';
  my $RowColor      = GetRowColor($State, $DaysInactive);
  my $PortLabel     = GetPortLabel($Port);

  my $PortLabelCell = '';
  if (($State eq 'Active') and ($PortLabel eq '&nbsp;')) {
    $PortLabelCell = "class=cellWarning";
  }

  $logger->debug("returning");
  return <<PORTINFOCELLS;

<tr class="$RowColor">
<td$RowSpan2>$PortName</td>
<td align="center"$RowSpan2>$VlanNbr</td>
<td align="center"$RowSpan2>$State</td>
<td align="center"$RowSpan2>$DaysInactive</td>
<td align="center"$RowSpan2>$Speed</td>
<td align="center"$RowSpan2>$Duplex</td>
<td$RowSpan2 $PortLabelCell>$PortLabel</td>
PORTINFOCELLS
}


sub GetEtherChannelCells ($) {
  my $Port = shift;
  my $logger = get_logger('log5');
  $logger->debug("called");

  my $EtherChannel = $Port->{EtherChannel}; # get the EtherChannel object
  my $EcPortList = '';
  foreach my $ChildPort (@{$EtherChannel->{ChildPorts}}) {
    $logger->debug("looking at maybe adding $ChildPort->{Name} to EcPortList");
    next if $ChildPort->{Name} eq $Port->{Name}; # don't want this port in the etherchannel port list
    $logger->debug("adding $ChildPort->{Name} to EcPortList");
    $EcPortList .= ' ' . $ChildPort->{Name};
  }
  my $ColSpan = ($Port->{CdpCachePlatform} ne '') ? 4 : 5;
  $logger->debug("returning");
  return <<EXTRAROW;
<tr>
<td colspan="$ColSpan" class="cellEtherChannel"><em>etherchanneled with $EcPortList</em></td>
</tr>
EXTRAROW
}


my %uniqueIpAddresses;

sub getUniqueIpAddresses() {
  return keys %uniqueIpAddresses;
}


# Given a port, return the second half of the table row for the port.
# The second half is the "information about what the port is connected
# to" part.
sub GetPortConnectedToCells ($$$$$) {
  my $Port                           = shift;
  my $RowSpan2                       = shift;
  my $MacIpAddrRef                   = shift;
  my $MacHostNameRef                 = shift;
  my $DepthBelowDestinationDirectory = shift;
  my $logger = get_logger('log4');
  my $PortName = $Port->{Name};
  $logger->debug("called for port \"$PortName\"");

  my $PortConnectedToCells;
  my $State = $Port->{State};
  if (($State eq 'Active') or $Port->{IsVirtual}) {
    my $WhatViaCdp = GetWhatViaCdp($Port, $DepthBelowDestinationDirectory);
    $PortConnectedToCells .= "<td$RowSpan2>$WhatViaCdp</td>\n"; # what (via CDP) column
    my $WhatViaLLDP = GetWhatViaLLDP($Port);
    $PortConnectedToCells .= "<td$RowSpan2>$WhatViaLLDP</td>\n";
    if ($Port->{IsTrunking} and           # if the port is trunking and
        !$Port->{IsConnectedToIpPhone}) { #    it's not a phone port
      my $trunkString = 'trunk port';
      if ($Port->{VlansOnTrunk} ne '') {
        my @items = split ' ', $Port->{VlansOnTrunk};
        my $nbrVlans = @items;
        my $limit = 10;
        if (defined($ThisSite::TrunkVLANLimit)) { 
            $limit = $ThisSite::TrunkVLANLimit; 
        }
        if ($nbrVlans <= $limit) {
          $trunkString .= " for VLANs $Port->{VlansOnTrunk}";
        } else {
          $trunkString .= " for more than $limit VLANs";
        }
      }
      $PortConnectedToCells .= "<td colspan=\"4\" align=\"center\"><em>$trunkString</em></td>";
    } else {
      my $NbrMacs = keys %{$Port->{Mac}};
      $logger->debug("NbrMacs = $NbrMacs");
      if ($NbrMacs > 0) {      # if one or more MACs exist on the port
        if ($NbrMacs > $ThisSite::PortMacLimit) {
          $PortConnectedToCells .= "<td colspan=\"4\"><em>$NbrMacs MACs connected to this port, display limit is $ThisSite::PortMacLimit</em></td>";
        } else {
          my @HostMacIps;
          my $OuiCodeMapRef = OuiCodes::GetOuiCodeMap;
          my $KludgeDelimeter = '#';
          foreach my $PortMac (keys %{$Port->{Mac}}) {
            next if $PortMac eq '';
            my $first6 = substr $PortMac, 0, 6;
            my $oc = (exists $$OuiCodeMapRef {$first6 }) ? $$OuiCodeMapRef {$first6 } : 'unknown'; # NIC Manufacturer
            my $ia = (exists $$MacIpAddrRef  {$PortMac}) ? $$MacIpAddrRef  {$PortMac} : '&nbsp;' ; # IP Address
            my $hn = (exists $$MacHostNameRef{$PortMac}) ? $$MacHostNameRef{$PortMac} : '&nbsp;' ; # DNS Name
            push @HostMacIps, join $KludgeDelimeter, $PortMac, $oc, $ia, $hn;
          }
          my (@mmacs, @orgs, @ipas, @hnames);
          foreach (sort @HostMacIps) {
            my ($mac, $org, $ipaddr, $hostname) = split $KludgeDelimeter, $_;
            push @mmacs,  $mac;
            push @orgs,   $org;
            push @ipas,   $ipaddr;
            if ($ipaddr ne '&nbsp;') {
              $uniqueIpAddresses{$ipaddr}++;
            }
            push @hnames, ($hostname eq '') ? '&nbsp;' : $hostname;
          }
          foreach my $org (@orgs) {
            $org =~ s/ /&nbsp;/go; # don't let the browser put breaks in the NIC Manufacturer values
          }
          my $cellColor = ($NbrMacs > $ThisSite::PortMacLimit ) ? "class=cellMacLimit" : '';
          $PortConnectedToCells .=
            "<td $cellColor class=\"mac-address\">" . join('<br>', @mmacs)  . "</td>\n" .
            "<td $cellColor align=\"center\">"      . join('<br>', @orgs)   . "</td>\n" .
            "<td $cellColor align=\"center\">"      . join('<br>', @ipas)   . "</td>\n" .
            "<td $cellColor align=\"center\">"      . join('<br>', @hnames) . "</td>";
        }
      } else {                  # no MACs exist on the port
        if ($Port->{ArpMacCount} > $ThisSite::ArpMacLimit) {
          my $tooManyCount = $Port->{ArpMacCount};
          $PortConnectedToCells .= "<td colspan=\"4\"><em>$tooManyCount MACs in ARP cache, display limit is $ThisSite::ArpMacLimit</em></td>";
        } elsif ($Port->{Type} == 6) { # 6 = ethernetCsmacd
          $PortConnectedToCells .= "<td colspan=\"4\"><em>port is active, but no packets have been seen recently</em></td>";
        } else {
          $PortConnectedToCells .= "<td colspan=\"4\">&nbsp;</td>";
        }
      }
    }
  } else {                      # else state is not active
    my $Color = ($State eq 'Disabled') ? "class=cellWarning" : '';
    $PortConnectedToCells .= "<td colspan=\"6\" $Color>&nbsp;</td>";
  }
  $PortConnectedToCells .= "\n</tr>\n";

  if ($Port->{EtherChannel}) {                # if the port is part of an EtherChannel
    $PortConnectedToCells .= GetEtherChannelCells($Port);
  }
  $logger->debug("returning");
  return $PortConnectedToCells;
}


sub MakeHtmlRow ($$$$$) {
  my $Switch                         = shift;
  my $Port                           = shift;
  my $MacIpAddrRef                   = shift;
  my $MacHostNameRef                 = shift;
  my $DepthBelowDestinationDirectory = shift;
  my $logger = get_logger('log3');
  my $PortName = $Port->{Name};
  $logger->debug("called for $PortName");

  # if we're etherchanneled, we'll need 2 rows, not one
  my $RowSpan2 = $Port->{EtherChannel} ? ' rowspan="2"' : '';

  my $HtmlRow = GetPortInfoCells($Port, $RowSpan2, $DepthBelowDestinationDirectory) .
                GetPortConnectedToCells($Port, $RowSpan2, $MacIpAddrRef, $MacHostNameRef, $DepthBelowDestinationDirectory);

  $logger->debug("returning");
  return $HtmlRow;
}


#
# This function creates a directory if it doesn't exist, and deletes
# it's contents if it does.
#
sub SetupDirectory ($) {
  my $Directory = shift;
  my $logger = get_logger('log5');
  $logger->debug("called to setup $Directory");

  if (-d $Directory) {          # if the directory exists
    my $deleted = unlink glob (File::Spec->catfile($Directory, '*'));
    $logger->debug("deleted $deleted files from $Directory");
  } else {
    $logger->debug("creating $Directory");
    mkdir $Directory or do {
      $logger->fatal("Couldn't create $Directory, $!");
      exit;
    };
  }
}


#
# Trim trailing whitespace.
#
sub trim ($) {
  my $inArg = shift;
  $inArg =~ s/ *$//;
  return $inArg;
}


#
# Given a file path that starts at the $DestinationDirectory, return
# a count of the number of directories that the path is "below" the
# $DestinationDirectory.  For example, suppose $DestinationDirectory
# is set to
#
#  /usr/web/nets/internal/portlists
#
# and this subroutine is called with this argument:
#
#  /usr/web/nets/internal/portlists/ports/gigeportspervlan
#
# This subroutine would return 2.
#
sub GetDirectoryDepth($) {
  my $Path = shift;

  my $DDLen = length $ThisSite::DestinationDirectory;
  if (substr($Path, 0, $DDLen) ne $ThisSite::DestinationDirectory) {   # this is a basic sanity check
    my $dd = $ThisSite::DestinationDirectory;
    die "GetDirectoryDepth called with \"$Path\", which doesn't start with $dd, exiting\n";
  }
  my @DestinationDirectoryPieces = File::Spec->splitdir($ThisSite::DestinationDirectory);
  my @PathPieces = File::Spec->splitdir($Path);
  return $#PathPieces - $#DestinationDirectoryPieces;
}

1;
