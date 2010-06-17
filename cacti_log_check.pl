#!/usr/bin/perl -w 
use strict ; 
use IO::Handle ; 
use Time::Local ; 
use POSIX qw(setsid) ; 
use Getopt::Long ; 


# Global oize variables 

my $log_loc = "/var/www/html/cacti/log/cacti.log" ;
my $naptime = 300 ; 
my $checktime = 300 ; 

my %o = ( 'log_loc' => \$log_loc , 
    'naptime' => \$naptime , 
    'checktime' => \$checktime ) ; 

#######

# put STDOUT AND STDERR as "/dev/null" if no logging file name is given 

my $log_file = "/dev/null" ; 

$o{"log_file"} = \$log_file ; 

options_processing ( \%o ) ; 

if ( exists $o{"daemonize"} ) { 
  daemonize($log_file) ; 
}


log_processing ( $log_loc , $naptime , $checktime , \%o ) ; 

sub options_processing { 
  my $o = shift ; 
  GetOptions ( $o , 'log_loc=s' , 'naptime=i' , 'checktime=i' , 'daemonize' , 'warning' , 'log_file=s' , 'grep=s' ) ; 

}


sub daemonize { 
     my $log_file = shift ; 
# Fork off a process  
     my $pid = fork() ; 
     die "couldn't create a child process : $!" if ( $pid < 0 ) ; 
     if ( $pid > 0 ) { 
# parent processs exit 
       exit () ;
     } 
     print " Daemon now goes in background with process id : $$ \n log File : $log_file \n " ; 
     setsid() ; 
     chdir ("/") ; 
     umask("0") ; 
     $| = 1;
     open STDIN , "/dev/null" or die " Can't open /dev/null for reading : $! " ; 
     open STDOUT , ">>$log_file" or die "Can't open $log_file for writing : $! " ; 
     open STDERR , ">>$log_file"  or die "Can't open $log_file for writing : $! " ; 

}

sub  log_processing { 
  my $loc = shift ; 
  my $naptime = shift ; 
  my $check_time = shift ; 
  my $o = shift ; # Passwd the whole options hash 
  open ( LOGFILE , "$loc" ) or die "Can't open $loc : $! " ; 

  for ( ; ; ) { 
    my $err_flag = 0 ; 
    my $err_count = 0 ; 
    my $warn_count = 0 ; 
    while ( <LOGFILE> ) { 
      my $cur = $_ ; 
      if ( $cur =~ /(ERROR:|WARNING:)/ ) { 
        my $err = 0 ; 
        $err = 1 if ( $1 =~ /ERROR:/ ) ; 
        if ( $cur =~ m/(\d\d)\/(\d\d)\/(\d\d\d\d)\s+(\d\d):(\d\d):(\d\d)\s+([A-Z]+)/ ) { 
              my ($mm,$dd,$yyyy,$h,$m,$s,$ref) = ($1,$2,$3,$4,$5,$6,$7) ; 
              if ( $ref =~ /AM/ ) { 
                if ( $h == 12 ) { 
                  $h = 0 ; 
                }
              } elsif (( $ref =~ /PM/ ) && ( $h != 12 ) ) { 
                $h += 12 ; 
              }

              $yyyy = $yyyy - 1900 ; 
              my $TIME = timelocal($s,$m,$h,$dd,$mm-1,$yyyy) ; 
              my $cur_epoch = timelocal((localtime)[0..5]) ;
              my $time_diff = ( $cur_epoch - $TIME ) ; 
              if  (  ( $time_diff <  $check_time  )  && ( $time_diff > 0 ) ) { 
                $err_flag = 1 ; 
                $err_count += 1  if ( $err == 1 ) ; 
                $warn_count += 1  if ( $err == 0 ) ;  
                if ( exists $o->{"grep"} ) { 
                    my $grep_str = $o->{"grep"} ; 
                    print   "$cur\n" if ( $cur =~ /$grep_str/ ) ; 
                }else { 
                  print "$cur\n"; 
                }
              }
        }
      }
    }
    if ( $err_flag == 1 ) { 
      print "Total errors : $err_count \n "; 
      print "Total warning : $warn_count \n "; 
    }
    sleep $naptime ; 
    LOGFILE->clearerr() ; 
  }
}
