#!/usr/bin/env perl
my $version = "ver0.1";
my $command = "$0";
my $i = 0;
my $start_run = time();
$ENV{GAP} = "/home/people/s142495/project/gene2annot";
while (defined($ARGV[$i])){
  $command .= " $ARGV[$i]";
  $i++;
}
use KyotoCabinet;
use Getopt::Std;
use Time::HiRes;
use Cwd;
use strict;
use lib "$ENV{GAP}/Parallel";
use Parallel::ChildManager;
use lib '/cm/local/apps/environment-modules/3.2.10/init/';
use perl;
my $prog_n50 = "$ENV{GAP}/scripts/n50.pl";

#############################################################
#
# Process command line
#
#############################################################

getopts('hi:o:Vvl:d:f:t:e:o:p:c:k') or Usage();
if (defined($Getopt::Std::opt_V)){
    print "$version\n";
    exit;
}

module("load tools prodigal/2.6.2");
my $prog_prodigal = "prodigal";
my $prog_diamond = "/home/people/s142495/programs/diamond-0.7.9/bin/diamond";
my $dbf = tie(my %dbf, 'KyotoCabinet::DB', "$ENV{GAP}/databases/pfam.kch");
my $cores = 4;
my $datestring;
my $verbose = 0;
my $cleanup = 0;
my $workingDir = $$;
my $MinNucSeqLength = 90;
my $num_fasta_entries_in_chunks = 0;
my $evalue = 0.001;
my @diamond_filenames;
my @diamond_commands;
my @convert_commands;
my @tmp_files;
*LOG = *STDERR;
#
# Usage
#
if (defined($Getopt::Std::opt_h)){
  # Print help message
  Usage();
}

sub Usage {
  print ("Usage: $0 [-h] [-l name] [-v] [-i name] [-c cores] [-V]\n");
  print ("Description:\n");
  print ("$0 - converting contig files to gene annotations\n");
  print ("\n");
  print ("Options:\n");
  print ("  -h  : display this message\n");
  print ("  -V  : show version \($version\) and exit\n");
  print ("  -i  : input fasta file\n");
  print ("  -f  : input list of fasta files\n");
  print ("  -c  : number of cores [$cores]\n");
  print ("  -v  : verbose mode [default off]\n");
  print ("  -l  : logfile [STDERR]\n");
  print ("  -d  : output directory [$workingDir]\n");
  print ("  -t  : minimum sequence length threshold [default $MinNucSeqLength]\n");
  print ("  -e  : e-value cutoff [default $evalue]\n");
  print ("  -k  : keep temporary files\n");
  exit;
}
# Usage
#
# A working directory for all output files
#
if (defined($Getopt::Std::opt_c)){
    $cores = $Getopt::Std::opt_c;
}
my $cm = new ChildManager($cores);

if (defined($Getopt::Std::opt_d)){
    $workingDir = $Getopt::Std::opt_d;
}
if (! -d $workingDir) {
    system("mkdir -p $workingDir");
    print LOG "a directory $workingDir was created\n" if ($verbose);
}

if (defined($Getopt::Std::opt_v)){
    $verbose = 1;
}

if (defined($Getopt::Std::opt_k)){
    $cleanup = 1;
}

if (defined($Getopt::Std::opt_l)){
    open(LOG, ">", "$workingDir/$Getopt::Std::opt_l");
}

if (defined($Getopt::Std::opt_t)){
    $MinNucSeqLength = $Getopt::Std::opt_t;
}

if (defined($Getopt::Std::opt_e)){
    $evalue = $Getopt::Std::opt_e;
}

my $contigFile;
if (defined($Getopt::Std::opt_i)){
    $contigFile = $Getopt::Std::opt_i;
    chomp $contigFile;
    my $n50 = `$prog_n50 -i $contigFile`;
    chomp $n50;
    print LOG "$contigFile\t$n50\n" if ($verbose);
    if (! -e $contigFile){
	print STDERR "File not found: $contigFile\n";
	die;
    }
} elsif (defined($Getopt::Std::opt_f)){
    open(LIST, "<", $Getopt::Std::opt_f);
    my $cmd= "cat";
    while (defined(my $file=<LIST>)){
       	chomp $file;
	my $n50 = `$prog_n50 -i $file`;
	chomp $n50;
	print LOG "$file\t$n50\n" if ($verbose);
	if (-e $file){
	    $cmd .= " $file";
	}
	else{
	    print STDERR "File not found: $file\n";
	    die;
	}
    }
    close LIST;
    $cmd .= " > $workingDir/contigs.fasta";
    print LOG "# Doing: $cmd\n" if ($verbose);
    system("$cmd");
    $contigFile = "contigs.fasta";
}
###############################################################################
#
# Main program start
#
###############################################################################

$datestring = localtime();
print LOG "## Local date and time $datestring - start program\n" if ($verbose);
print LOG "# $command\n" if ($verbose);

# Process fasta file and select sequences longer than the selected $MinNucSeqLength

my $SelectedFasta = "$workingDir/contigs.threshold";
push(@tmp_files, $SelectedFasta);
if ((! -e $SelectedFasta) or (-z $SelectedFasta)){
    &select_fasta($MinNucSeqLength, $contigFile, $SelectedFasta);
}

###############################################################################
# Doing prodigal
###############################################################################
my $cmd;
my $prodigalFasta="$workingDir/prodigal.fasta";
if ((! -e $prodigalFasta) or (-z $prodigalFasta)){
    $cmd = "$prog_prodigal -i $SelectedFasta -a $prodigalFasta -p meta >& /dev/null";
    print LOG "# Doing: $cmd\n" if ($verbose) ;
    system("$cmd");
}

#Split the prodigal file into chunks and process them with diamond
&splitfasta($prodigalFasta, $workingDir);

################################################################################
# Doing diamond
################################################################################
foreach my $cmd (@diamond_commands) {
    print LOG "# Doing: $cmd\n" if ($verbose);
    $cm -> start("$cmd");
}
$cm -> wait_all_children;

foreach my $cmd (@convert_commands) {
    print LOG "# Converting to BLAST readable files: $cmd\n" if ($verbose);
    system("$cmd");
}

my $diamond_cat = "$workingDir/diamond.pfams.m8";
system("cat $workingDir/*.m8 > $diamond_cat");

###############################################################################
# Pfam counts, adding pfam column to diamond file
###############################################################################
&pfamfinder($diamond_cat, $dbf); 

undef($dbf);
untie(%dbf);

###############################################################################
# Doing statistics - prodigal genes, dmnd finds, pfam annotations
###############################################################################
my $statistics_file = "$workingDir/statistics.log";
my $prodigal_genes = `grep "^>" $prodigalFasta | wc -l`;
chomp $prodigal_genes;
my $diamond_annotations = `wc -l < $diamond_cat`;
chomp $diamond_annotations;
my $unannotated = $prodigal_genes - $diamond_annotations;
my $percentage_unannotated = ($unannotated/$prodigal_genes)*100;
my $percentage_annotated = 100 - $percentage_unannotated;
my $pfam_families = `wc -l < $workingDir/pfam.counts`;
chomp $pfam_families;
open(STAT, ">", $statistics_file) or die "can't open $statistics_file, reason: $!\n";
print STAT "Number of prodigal genes found:\t$prodigal_genes\nNumber of diamond pfam annotations:\t$diamond_annotations\nNumber of unannotated genes:\t$unannotated\nNumber of unique pfam families:\t$pfam_families\n";
printf STAT "Percentage unannotated:\t%.2f\n", $percentage_unannotated;
printf STAT "Percentage annotated:\t%.2f\n", $percentage_annotated;
close STAT;

###############################################################################
# Removing temporary files (if -k is not defined)
###############################################################################
if ($cleanup == 0) {
    foreach my $file (@tmp_files) {
	system("rm $file");
    }
}

###############################################################################
#
# Subroutines
#
###############################################################################
# Threshold output file
sub select_fasta {
    my ($thresh, $inputFile, $outputFile) = @_;
    my $contig_length = 0;
    my $contigs = '';
    my $tmp_header = '';
    open(IN,"<", $inputFile) or die "can't open $inputFile ,reason: $!\n";
    open(OUT, ">", $outputFile) or die "can't open $outputFile ,reason: $!\n";
    while (defined(my $line = <IN>)) {
	if ($line =~ m/^>/) {
	    print OUT $tmp_header if $contig_length > $thresh;
	    print OUT $contigs if $contig_length > $thresh;
	    $tmp_header = $line;
	    $contig_length = 0;
	    $contigs = '';
	} else {
	    $contigs .= $line;
	    $contig_length += length($line)-1;
	}
    }
    print OUT $tmp_header if $contig_length > $thresh;
    print OUT $contigs if $contig_length > $thresh;
}

# Chunk prodigal file and diamond processing
sub splitfasta {
    my ($file, $output) = @_;
    my $total_prodigal_entries = `grep "^>" $file | wc -l`;
    chomp $total_prodigal_entries;
    $num_fasta_entries_in_chunks = int($total_prodigal_entries/$cores)+1;
    my $i = 0;
    my @files;
    my $num_sequences = 0;
    my $aa_seq = '';
    my $tmp_header = '';
    my $sequence_length = 0;
    my $min_aminoacids = int($MinNucSeqLength/3);
    my $filename = "$output/prodigal.fasta.$i";
    open(OUT, ">", $filename) or die "can't open $filename ,reason: $!\n";
    open(IN, "<", $file) or die "can't open $file ,reason: $!\n";

    while (defined(my $line = <IN>)) {
	if ($num_sequences == $num_fasta_entries_in_chunks) {
	    push(@files, $filename);
	    push(@tmp_files, $filename);
	    close OUT;
	    $i++;
	    $num_sequences = 0;
	    $filename = "$output/prodigal.fasta.$i";
	    open(OUT, ">", $filename) or die "can't open $filename ,reason: $!\n";
	}

	if ($line =~ m/^>/) {
	    if ($sequence_length >= $min_aminoacids) {
		print OUT $tmp_header unless $tmp_header eq '';
		print OUT $aa_seq unless $tmp_header eq '';
		$num_sequences++ unless $tmp_header eq '';
	    }
	    $tmp_header = $line;
	    $aa_seq = '';
	    $sequence_length = 0;
	} else {
	    # not counting new line
	    $sequence_length += length($line)-1;
	    $aa_seq .= $line;
	}
    }
    close IN;
    # print out the last sequence
    if ($sequence_length >= $min_aminoacids) {
	print OUT $tmp_header unless $tmp_header eq '';
	print OUT $aa_seq unless $tmp_header eq '';
	$num_sequences++ unless $tmp_header eq '';
    }
    push(@files, $filename);
    push(@tmp_files, $filename);
    close OUT;

    my $diamondcmd;
    my $convert_to_BLAST;
    my $extension = ".daa";
    foreach my $el (@files) {
	if ((-e $el) or (! -z $el)) {
	    my $dmnd_out = "$el.diamond";
	    my $dmnd_out_h = "$el.diamond.m8";
	    $diamondcmd = "$prog_diamond blastp -d ./databases/Pfam-A.diamond.dmnd -q $el -a $dmnd_out -k 1 -e $evalue -t $output -c 1";
	    $convert_to_BLAST = "$prog_diamond view -a $dmnd_out$extension -o $dmnd_out_h -f tab";
	    push(@tmp_files, $dmnd_out_h);
	    push(@tmp_files, "$dmnd_out$extension");
	    push(@diamond_filenames, $dmnd_out);
	    push(@diamond_commands, $diamondcmd);
	    push(@convert_commands, $convert_to_BLAST);
	}
    }
}

# Count pfams,cat diamond files in one,  append pfam column to the diamond output file
sub pfamfinder {
    my ($file, $db) = @_;
    my %pfam_count;
    my @annot_pfam;
    my $description = "# Qname\tSname\t%id\tAlen\tmismatches\tgaps\tQstart\tQend\tSstart\tSend\tbit-score\te-value\tpfam\n";
    push(@annot_pfam, $description);
    open(DM, "<", $file) or die "$!\n";
    while (defined(my $line = <DM>)) {
	chomp $line;
	if ($line =~ m/\S+\s+(\S+)\s+/) {
	    my $match = $1;
	    my $pfam_acc = '';
	    my $value = $db->get($match);
	    if (defined($value)){
		$pfam_acc = $value;
	    }
	    my $query_pfam = "$line\t$pfam_acc\n";
	    push(@annot_pfam, $query_pfam);
	    chomp $pfam_acc;
	    $pfam_count{$pfam_acc} += 1 if exists $pfam_count{$pfam_acc};
	    $pfam_count{$pfam_acc} = 1 if not exists $pfam_count{$pfam_acc};
	}
    }
    close DM;
    open(OUT, ">", $file) or die "$!\n";
    print OUT @annot_pfam;
    close OUT;
    my $pfam_count_file = "$workingDir/pfam.counts";
    open(COUNTS, ">", $pfam_count_file) or die "$!\n";
    foreach my $el (sort {$pfam_count{$b} <=> $pfam_count{$a}} keys %pfam_count) {
	print COUNTS "$el $pfam_count{$el}\n";
    }
    close COUNTS;
}
################################## END ############################################
my $end_run = time();
my $run_time = $end_run - $start_run;
print LOG "# Total walltime: $run_time seconds\n" if ($verbose);
