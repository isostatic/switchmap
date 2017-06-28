package IanaMibConstants;

#
# This module exists to encapsulate the IANAifTypes hash.
#

use strict;
use Log::Log4perl qw(get_logger);
#use Data::Dumper;


my %IANAifTypes;

#
# Read the ianaiftype-mib.txt and create the IANAifTypes hash.
#
sub initialize () {
  my $logger = get_logger('log1');
  my $logger7 = get_logger('log7');
  $logger->debug("called");

  # load the chassis ciscoProducts OIDs, indexed by ciscoProduct (1) OIDs
  $logger->info("reading $Constants::IanaIfTypeMibFile");
  open IANA_IF_TYPE_MIB_FILE, "<$Constants::IanaIfTypeMibFile" or do {
    $logger->fatal("Couldn't open $Constants::IanaIfTypeMibFile for reading, $!");
    exit;
  };

  # skip the header lines
  while (<IANA_IF_TYPE_MIB_FILE>) {
    last if /IANAifType ::= TEXTUAL-CONVENTION/;
  }

  # skip the description
  while (<IANA_IF_TYPE_MIB_FILE>) {
    last if /SYNTAX\s+INTEGER/;
  }

  my $pcount = 0;
  while (<IANA_IF_TYPE_MIB_FILE>) {
    chomp;
    last if /\s+}$/;
    next if !/\s+(\w+)\s?\((\d+)\)/;
    my $ifTypeString = $1;
    my $ifTypeNumber = $2;
    $IANAifTypes{$ifTypeNumber} = $ifTypeString;
    $pcount++;
    $logger7->info("ifTypeNumber = $ifTypeNumber\t= \"ifTypeString\"");
  }
  close IANA_IF_TYPE_MIB_FILE;
  $logger->info("got $pcount interface types");

  $logger->debug("returning");
}


sub getIanaIfType ($) {
  my $ifTypeNumber = shift;
  return '' if !exists $IANAifTypes{$ifTypeNumber};
  return $IANAifTypes{$ifTypeNumber};
}

1;
