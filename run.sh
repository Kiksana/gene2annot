#!/bin/tcsh

module load tools torque moab/8.1.1 perl/5.20.1

xqsub -V -d /home/people/s142495/project/gene2annot -l nodes=1:ppn=4,mem=30gb,walltime=1:00:00 -de ./gene2annot.pl -i test.chunk.bacteria.fasta -v -l gene2ann.log -d chunk_bacteria
