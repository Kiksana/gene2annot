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
  print ("  -i  : input file name [STDIN]\n");
  print ("  -o  : output file name [STDOUT]\n");
  print ("  -l  : logfile [STDERR]\n");
  print ("  -v  : Verbose [off]\n");
  print ("\n");
 exit;
} # Usage

#
# Open input
#
if (not defined($Getopt::Std::opt_i)){
  # Read from standard input
  *INP = *STDIN;
} 
else{
  # Read from file
  if (($Getopt::Std::opt_i=~/\.gz$/) || ($Getopt::Std::opt_i=~/\.Z$/)){
    open(INP,"gunzip -c $Getopt::Std::opt_i |") || die ("can't open file $Getopt::Std::opt_i: $!");
  }
  else{
    open(INP,"<$Getopt::Std::opt_i") || die ("can't open file $Getopt::Std::opt_i: $!");
  }
}
#
# If not file name is given, use standard output
#
if (not defined($Getopt::Std::opt_o)){
  # Output goes to std output
  *OUT = *STDOUT;
} else {
  # Open file to write to
  open(OUT, ">$Getopt::Std::opt_o") || die ("can't open file $Getopt::Std::opt_o: $!");
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

my $contigFile;
my @contigs=();
my $totalLength = 0;
my $num_seq = 0;
my $contig_length = 0;
while (defined(my $line = <INP>)) {
  chomp $line;
  if ($line =~ m/^>/) {
    push(@contigs, $contig_length-1) unless $contig_length == 0;
    $contig_length = 0;
    $num_seq++;
  } else {
    $totalLength += length($line);
    $contig_length += length($line);
  }
}
push(@contigs, $contig_length-1);
$totalLength -= $num_seq; #get rid of the new lines
close INP;

@contigs = sort {$b <=> $a} @contigs;

my $limit = ($totalLength/2);
my $N50 = 0;
my $count = 0;
foreach my $len_contig (@contigs) {
  $count += $len_contig;
  $N50 = $len_contig if $count > $limit;
  last if $count > $limit;
}

print OUT "Number of Seq = ". $num_seq, " Total length = ". $totalLength, " Shortest Seq = ". pop@contigs, " Longest Seq = ". shift@contigs, " N50 value = ". $N50, "\n";
