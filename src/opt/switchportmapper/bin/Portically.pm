#!/usr/bin/perl -w

package Portically;

use strict;
use List::Util qw[min max];

# The SwitchMap programs sorts port names in several places, using the
# Perl "sort" function.  It also uses the sort function to sort
# machine names.  By default, the Perl sort algorithm sorts
# "ASCIIbetically", so that "2/11" ends up before "2/1", and "108"
# ends up before "2" and "ml-mr-c10-gs" ends up before "ml-mr-c2-gs".
# The PortSort subroutine sorts Cisco port names in the way that's
# expected by humans.
#
# Example Cisco IOS network interface names that have been
# seen "in the wild":
#
#       5/7
#       As0/1/0
#       Fa2/1
#       Gi0/1
#       Gi11/7/1
#       Lo0
#       Mu1
#       Se0/0/1:0
#       T1 0/0/1
#       Te4/2
#       Tu1
#       FastEthernet0/0.406   (maybe only in configs)
#       SPAN RP
#       CPP
#       Te6/4
#       Te6/4--Controlled
#       Te6/4--Uncontrolled
#       Te6/40
#       Te6/40--Controlled
#       Te6/40--Uncontrolled
#

my $DIGIT = 1;
my $NOTDIGIT = 2;

sub getCharType($) {
  my $char =shift;
  return ($char =~ /\d/) ? $DIGIT : $NOTDIGIT;
}

#
# Given a string, return the fragment at the beginning of the string
# that consists of all digits or all nondigits.
#
sub getFirstFragment($) {
  my $portName = shift;
  return '' if length $$portName == 0;
#  print "getFirstFragment: called, portName = \"$$portName\"\n";
  my $fragment = '';
  my $firstCharType = getCharType(substr $$portName, 0, 1);

  while (length $$portName != 0) {
    my $char = substr $$portName, 0, 1;     # get the first character
#    print "getFirstFragment: char = \"$char\", charType = $charType\n";
    if (getCharType($char) == $firstCharType) {
      $fragment .= $char;
      $$portName = substr $$portName, 1;    # remove the first character
    } else {
      last;
    }
  }
#  print "getFirstFragment: returning \"$fragment\"\n";
  return $fragment;
}


# I used to have a complex approach to this, based on the syntax of
# Cisco port names - I split out the leading "media" part and compared
# that, then split the remainder on slashes or something.  It was a
# mess, and failed on special cases. I finally realized the a simple
# general algorithm: split each string into substrings composed of one
# of two kinds of characters: digits and nondigits. This allows the
# sequences of digits to be compared as numbers, so that "2" comes
# before "108". All sequences of nondigits are compared as strings.
#
sub portically {
  return 0 if (!defined $a) and (!defined $b);
  return -1 if !defined $a;
  return  1 if !defined $b;

#  print "\na = \"$a\", b = \"$b\"\n";
  my $localA = $a;  # make local copies that we can chop fragments off of
  my $localB = $b;
  for (;;) {
    my $aFragment = getFirstFragment(\$localA);
    my $bFragment = getFirstFragment(\$localB);
#    print "aFragment = \"$aFragment\", bFragment = \"$bFragment\"\n";

    last if ($aFragment eq '') and ($bFragment eq '');
    return -1 if ($aFragment eq '');
    return  1 if ($bFragment eq '');

    if (($aFragment =~ /\d/) and ($bFragment =~ /\d/)) { # if they are both numeric
      return -1 if $aFragment < $bFragment;              # use numeric comparisons
      return  1 if $aFragment > $bFragment;
    } else {
      return -1 if $aFragment lt $bFragment;             # use string comparisons
      return  1 if $aFragment gt $bFragment;
    }
  }
  return 0;
}


sub PortSort {
  return sort portically @_;
}


#  Testing:

# my @inlist = (
#               'Te6/40--Controlled',
#               'Gi5/4',
#               '5/7',
#               '7/13',
#               '7/9',
#               '8/3',
#               'As0/1/0',
#               'Fa2/1',
#               'FastEthernet0/0.406',
#               'Gi0/1',
#               'Gi1/2/1',
#               'Gi1/2/1duplicate',
#               'Gi1/2/1duplicate',
#               'Gi1/2/11',
#               'Gi1/2/12',
#               'FastEthernet0/0.700',
#               'Gi1/3/1',
#               'Gi1/3/2',
#               'Gi1/4/1',
#               'Gi1/4/2',
#               'Gi1/5/1',
#               '7/10',
#               'Gi1/7/1',
#               'Gi11/7/1',
#               'Gi12/7/1',
#               'Gi2/2/1',
#               'Gi2/7/2',
#               'Gi22/10/1',
#               'Gi22/17/1',
#               'Gi22/7/1',
#               'Lo0',
#               'Mu1',
#               'Se0/0/12:0',
#               'T1 0/0/1',
#               'Gi22/0/1',
#               'T1 0/0/0',
#               'Tu1',
#               '8/40',
#               '7/28',
#               '9/45',
#               '9/16',
#               '7/5',
#               'Gi2/3--Controlled',
#               '9/3',
#               'ml-mr-c1-gs',
#               'ml-mr-c2-gs',
#               '5/7',
#               'As0/1/0',
#               'Fa2/1',
#               'Gi0/1',
#               'Se0/0/1:0',
#               'Te4/2',
#               'FastEthernet0/0.406   (maybe only in configs)',
#               'SPAN RP',
#               'CPP',
#               'Te6/4',
#               'Te6/4--Controlled',
#               'Te6/4--Uncontrolled',
#               'Te6/40',
#               'Te6/40--Controlled',
#               'Te6/40--Uncontrolled',
#               'Gi2/1',
#               'Gi2/1--Controlled',
#               'Gi2/1--Uncontrolled',
#               'Gi2/10',
#               'Gi2/10--Controlled',
#               'Gi2/10--Uncontrolled',
#               'Gi2/11',
#               'Gi2/11--Controlled',
#               'Gi2/11--Uncontrolled',
#               'Gi2/2',
#               'Gi2/2--Controlled',
#               'Gi2/2--Uncontrolled',
#               'Gi22/3',
#               'Gi2/3',
#               'Gi2/3--Uncontrolled',
#               'Gi2/30',
#               'Gi2/31--Controlled',
#               'Gi2/31--Uncontrolled',
#               'Gi2/38--Uncontrolled',
#               'ml-mr-c10-gs',
#               'Gi2/39',
#               'Gi2/39--Controlled',
#               'Gi2/39--Uncontrolled',
#               'Gi2/4',
#               'Gi2/4--Controlled',
#               'Gi2/4--Uncontrolled',
#               'Gi2/40',
#               'Gi2/40--Controlled',
#               'Gi2/40--Uncontrolled',
#               'Gi2/5',
#               'Gi2/5--Controlled',
#               'Gi2/5--Uncontrolled',
#               'Gi2/6',
#               'Gi2/6--Controlled',
#               'Gi2/6--Uncontrolled',
#               'Gi2/7',
#               'Gi2/7--Controlled',
#               'Gi2/7--Uncontrolled',
#               'Gi2/8',
#               'Gi2/8--Controlled',
#               'Gi2/8--Uncontrolled',
#               'Gi2/9',
#               'Gi2/9--Controlled',
#               'Gi2/9--Uncontrolled',
#              );

# print "yo.\n";

# foreach (PortSort(@inlist)) {
#   print "sorted inlist = $_\n";
# }

1;

