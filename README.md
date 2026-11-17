# Heliconius_WGS_variant_calling

This repository contains re-analysis of low coverage whole-genome re-sequencing data from Supple et al. (2015) - https://doi.org/10.1186/s12862-015-0486-y. Steps of analysis from reference mapping to different variant calling strategies are described below.

1. Generate a list of accessions to be downloaded and store it in SraAccList.txt. We are going to download the raw data using prefetch+fasterq-dump

```
/path/to/sratoolkit/bin/prefetch --option-file SraAccList.txt
```
This will give you separate folders for each accession number with accession.sra file inside each folder. We want to obtain paired end fastq reads for corresponding sample. This can be done using following command -

```
find . -name "*.sra" | while read sra; do /path/to/sratoolkit/bin/fasterq-dump "$sra" --split-files --threads 8; done
```

2. Check quality of fastq reads using fastqc

Use script `All_pairs_synteny.sh`, where your species pairs along with their relative pair age (see background) are specified in file `pairs.txt`. Note that if this file was created in the mac system and then uploaded to cluster (unix environment), there will be standard characters (\t , \r, etc) present in the lines which will be carried to file names since they are 'attached' to the columns and are carried in the output filename. So, these characters have to be removed using dos2unix.

3. Reference mapping, generating sorted bam files and marking duplicate reads using sambamba (https://lomereiter.github.io/sambamba/docs/sambamba-markdup.html) can be done using script `ref_mapping.sh`

4. Check the general stats of sorted bam files using 'samtools flagstats'. This will tell you number of reads mapped to reference (mapping quality), reads flagged as primary and secondary, paired reads, reads properly paired, paired reads mapped each mapped to different chromosomes 
Note - If the number of paired reads mapped to different chromosomes is unusually high, it means the reference assembly was most likely fragmented. 

5. Variant calling from sorted bam files using BCFtools

```
bcftools mpileup --threads 20 -a AD,DP,SP -f /path/to/ref_assembly/H_erato_ref.fna /path/to/sorted_bam_files/*_sorted_dup.bam | bcftools call --threads 20 -f GQ,GP -m -Oz -o /output_folder/Heliconius/output.vcf.gz
```
The first part (mpileup) takes sequences from each bam file and concatenate it together in mpileup file. This step estimates genotype likelihood for each variant. -a option tells bcftools to annotate mpileup with additional quality scores. 
The second part (bcftools call): -m option activates multiallellic calling mode
-Oz compresses the output
-f GQ, GP includes geotype quality and Genotype probability in the output
Both variant and invariant sites are recommended to be included, as invariant positions are needed to correctly calculate stats such as pi and Dxy. 

6. Variant filtering

Count the number of snps in resulting vcf.gz file using awk or grep (grep works faster).

```
zcat output.vcf.gz | awk '!/\#/' | wc -l
```
OR

```
zcat output.vcf.gz | grep -v '#' | wc -l
```
a) Filter indels and multiallellic sites

```
bcftools filter -Ou -g 5:indel,other output.vcf.gz | bcftools view -Oz -M 2 -v snps > output_snps_only.vcf.gz
```
-g 5:indel,other will remove sites within 5 bp of indels
-M 2 option removes multiallellic sites
-v option keeps only snps, removing indels
-Ou option will output uncompressed bcf, which can be piped to next command which gives compressed vcf (-Oz)
Bcftools filter will filter files as using fixed thresholds

b)	(Site-level filter) Filter by total read depth per site (INFO/DP)
This is sum of total reads for a particular site across all positions. Here we filter by upper limit, as low read depth will be filtered by other steps. 

```
bcftools filter -Oz -e "INFO/DP>2.5*AVG(INFO/DP)" output_snps_only.vcf.gz > output_DP_filt.vcf.gz
```
-e option excludes values according to specified threshold

c)	Hard filters (site-level filters) - Filtering by mapping quality (MQ), site call quality (QUAL) and strand bias (SP)

mapping quality (MQ) - 
```
bcftools filter -Oz -e "MQ<30" output_DP_filt.vcf.gz > output_MQ_filt.vcf.gz
```

site call quality (QUAL) - 
```
bcftools filter -Oz -e "QUAL<30" output_MQ_filt.vcf.gz > output_QUAL_filt.vcf.gz
```

strand bias (SP) - 
```
bcftools filter -Oz -e "SP>3" output_QUAL_filt.vcf.gz > output_SP_filt.vcf.gz
```

d)	Soft filters – Filtering based on Genotype quality (GQ) and coverage for each sample (FMT/DP). We mask the genotypes that we do not trust by setting them as missing data. 
Depending on the data type, these filters can mask almost everything as a missing data, especially for low-coverage WGS (< 5x). 
If the distributions of GQ and FMT/DP are near zero, it means there are lots of genotypes with near-zero values for those quality scores. So it is best to avoid soft-filtering based on these altogether. Instead, we can filter based on just missing data. 

"F_MISSING" tag in the vcf file should be set to missing genotypes and'HIGH_MISS' tag to values greater than 20%

```
bcftools +fill-tags output_SP_filt.vcf.gz -- -t F_MISSING | bcftools filter -s "HIGH_MISS" -e 'F_MISSING > 0.2' output_SP_filt.vcf.gz -Oz -o output_soft_filtered.vcf.gz
```

The fill-tags option can be used to add tags in INFO field that are calculated but are not generally there (like fraction of missing genotypes F_MISSING, MAF, etc). 
Remove tagged values -

```
bcftools view -f "HIGH_MISS" output_soft_filtered.vcf.gz > output_final_filtered.vcf.gz
```
-f – apply threshold
