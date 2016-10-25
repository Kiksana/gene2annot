#!/usr/bin/env perl
my $command="$0 ";
my $i=0;
while (defined($ARGV[$i])){
  $command .= "$ARGV[$i] ";
  $i++;
}
use Getopt::Std;
use Cwd;
use strict;
# Default parameters
*LOG=*STDERR;
my $verbose=0;
#
# Process command line
#
getopts('hi:o:vl:')||Usage();
#
# Usage
#
if (defined($Getopt::Std::opt_h)||defined($Getopt::Std::opt_h)){
  # Print help message
  Usage();
}

sub Usage {
  print ("Usage: $0 [-h] [-i name] [-o name] \n");
  print ("Description:\n");
  print ("$0 - Read and write files\n");
  print ("\n");
  print ("Options:\n");
  print ("  -h  : display this message\n");
  print ("  -i  : input kch database name\n");
  print ("  -o  : output file name [STDOUT]\n");
  print ("  -l  : logfile [STDERR]\n");
  print ("  -v  : Verbose [off]\n");
  print ("\n");
 exit;
} # Usage

#
# If not file name is given, use standard output
#
if (not defined($Getopt::Std::opt_o)){
  # Output goes to std output
  *OUT = *STDOUT;
} else {
  # Open file to write to
  open(OUT, ">$Getopt::Std::opt_o") || die ("can't open file
$Getopt::Std::opt_o: $!");
}
if (defined($Getopt::Std::opt_l)){
    open(LOG,">$Getopt::Std::opt_l");
}
if (defined($Getopt::Std::opt_v)){
    $verbose=1;
}
###############################################################################
# Main
#
###############################################################################
my $datestring = localtime();
my $thisDir=cwd();
if ($verbose){
    print LOG "## Local date and time $datestring - Start program\n";
    print LOG "# $command\n";
    print LOG "# working dir: $thisDir\n\n";
}
use KyotoCabinet;

 # create the database object
my $db = new KyotoCabinet::DB;

 # open the database
if (!$db->open("$Getopt::Std::opt_i", $db->OWRITER | $db->OCREATE)) {
    printf STDERR ("open error: %s\n", $db->error);
}
# traverse records
my $cur = $db->cursor;
$cur->jump;
while (my ($key, $value) = $cur->get(1)) {
    printf("%s\t%s\n", $key, $value);
}
$cur->disable;
if (!$db->close) {
    printf STDERR ("close error: %s\n", $db->error);
}