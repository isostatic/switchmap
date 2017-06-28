package Timer;
#
#   Timer.pm - part of SwitchMap
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
# This file is intended to be included in other Perl scripts.
#
#
# These timer functions were written to satisfy these requirements:
#
# 1. Provide an elapsed time for the entire program
# 2. Provide elapsed times for major chunks of the main program - the
#    "major functions", to break down the phases of the program
# 3. Provide cumulative elapsed times for the "minor functions", which
#    might be called many times from many places in the program. Like,
#    how much total time is spent in the GetSnmpTable function?
# 4. Provide elapsed times for how much time is spent getting data
#    from each switch or router
# 5. Provide levels of timing, so a user can choose to see a little
#    timing data (just the main program, or main and the major
#    functions) or a lot of timing data
#
# In general, to time something, you call "new" to create a timer, then "start" to start it, then "end" to stop the timer.

#use strict;
use Time::HiRes;
use Log::Log4perl qw(get_logger :levels);


$NO_TIMERS      = 0;  # don't emit any messages (the default)
$MAIN           = 1;  # total elapsed time for the whole program
$MAJOR_FUNCTION = 2;  # total elapsed times spent in major functions
$MINOR_FUNCTION = 3;  # total elapsed times spent in minor functions
$DEVICE_NAME    = 4;  # total elapsed times spent getting each device's data

my $globalTimerLevel = 0;
my %timers;  # hash of hashes


sub setGlobalTimerLevel ($) {
  $globalTimerLevel = shift;
}


sub new {
  my $type         = shift;
  my $description  = shift;
  my $level        = shift;
  my $logger = get_logger('log3');
  $logger->debug("called");

  if (exists $timers{$description}) {
    return $timers{$description};
  } else {
    my $this = {};
    $this->{level} = $level;
    $this->{description} = $description;
    $timers{$description} = $this;
    $logger->debug("returning");
    return bless $this;
  }
}


sub start () {
  my $this = shift;
  my ($currentSeconds, $currentMicroSeconds) = Time::HiRes::gettimeofday;
  $this->{seconds} = $currentSeconds;
  $this->{microSeconds} = $currentMicroSeconds;
}


sub stop () {
  my $this = shift;
  my $logger = get_logger('log3');
  $logger->debug("called");
  if (!exists $this->{seconds}) {
    print$logger->error("method \"end\" called for timer \"$this->{name}\", but start hasn't been called first\n");
  } else {
    my $elapsed = Time::HiRes::tv_interval([$this->{seconds}, $this->{microSeconds}]);
    if (exists $this->{elapsed}) {
      $this->{elapsed} += $elapsed;
    } else {
      $this->{elapsed} = $elapsed;
    }
  }
  $logger->debug("returning");
}


#
# Display the timers. In general, we want the types of timers (levels)
# to be displayed together, with the most granular timers first and
# the most coarse (the timer of the whole program) last. Within each
# level, sort the timers (mostly so the list of switches is sorted).
#
sub display () {
  for (my $level=$globalTimerLevel; $level>=1; $level--) {
    my %sortedTimers;
    foreach my $timerName (keys %timers) {
      my $timer = $timers{$timerName};
      if ($timer->{level} eq $level) {
        $sortedTimers{$timer->{description}} = $timer;
      }
    }
    foreach my $description (sort keys %sortedTimers) {
      my $timer = $sortedTimers{$description};
      print $timer->{elapsed} . ' seconds ' . $timer->{description} . "\n";
    }
  }
}

1;
