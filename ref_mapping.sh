#!/bin/bash

inputdir="/storage/home/hcoda1/7/mjoshi96/scratch/Mukta/Heliconius/Raw_data/"
outdir="/storage/home/hcoda1/7/mjoshi96/scratch/Mukta/Heliconius/mapped/"
ref_seq=$1 #provide as a command line argument
#ref_seq ="/storage/home/hcoda1/7/mjoshi96/scratch/Mukta/Heliconius/H_erato_ref.fna"

bwa index $ref_seq

mkdir -p "$outdir"

for R1 in $inputdir/*_1.fastq;
do
R2=${R1/_1/_2}


Sample=$(basename "$R1" | sed 's/_1.*//')

echo "processing sample $Sample"
echo "forward read:$R1"
echo "reverse read:$R2"

bwa mem -k 30 $ref_seq $R1 $R2  > $outdir/${Sample}.sam
samtools view -bS $outdir/${Sample}.sam | samtools sort -o $outdir/${Sample}_sorted.bam

/storage/home/hcoda1/7/mjoshi96/scratch/Mukta/Heliconius/sambamba-1.0.1 markdup $outdir/${Sample}_sorted.bam $outdir/${Sample}_sorted_dup.bam

$outdir/${Sample}.sam

echo "done with $Sample"

done
