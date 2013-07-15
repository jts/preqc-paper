SHELL=/bin/bash -o pipefail

# Do not delete intermediate files
.SECONDARY:
#all: preqc_report.pdf sim_report.pdf

# SGA version
#SGA=sga-0.10.6
SGA=$(SGA_DEV)
DWGSIM=~/software/bin/dwgsim

#
# Short read input from the ENA
#

# Assemblathon snake (all short insert)
SNAKE_DIR=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR234/
SNAKE_RUNS=ERR234359 ERR234360 ERR234361 ERR234362 ERR234363 ERR234364 ERR234365 ERR234366 ERR234367 ERR234368 ERR234369 ERR234370 ERR234371 ERR234372 ERR234373 ERR234374

# Assemblathon Bird (500bp insert, 150bp read data)
BIRD_DIR=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR244/
BIRD_RUN=ERR244146

# Assemblathon Cichlid (short insert data)
CICHLID_DIR=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR077/
CICHLID_RUNS=SRR077286 SRR077287 SRR077290 SRR077292 SRR077298 SRR077300 SRR077301 SRR077302

# NA12878 (Study accession: ERP001229)
HUMAN_DIR=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR091/
HUMAN_RUNS=ERR091571 ERR091572 ERR091573 ERR091574

# Oyster
OYSTER_DIR=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/SRR322/
OYSTER_RUNS=SRR322874 SRR322875 SRR322876 SRR322877

# S. cerevisae
# This set is over 500X so we downsample it to ~40X
YEAST_DIR=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR049/
YEAST_RUN=ERR049929

#
# Short read data sets
#

# Download and preprocess every data set
snake.fastq.gz:
		rm -f $@
		$(foreach id, $(SNAKE_RUNS), \
            $(SGA) preprocess --pe-mode 1 \
            <(curl $(SNAKE_DIR)/$(id)/$(id)_1.fastq.gz | zcat) \
            <(curl $(SNAKE_DIR)/$(id)/$(id)_2.fastq.gz | zcat) | gzip >> $@;)

bird.fastq.gz:
		$(SGA) preprocess --pe-mode 1 \
            <(curl $(BIRD_DIR)/$(BIRD_RUN)/$(BIRD_RUN)_1.fastq.gz | zcat) \
            <(curl $(BIRD_DIR)/$(BIRD_RUN)/$(BIRD_RUN)_2.fastq.gz | zcat) | gzip > $@

fish.fastq.gz:
		rm -f $@
		$(foreach id, $(CICHLID_RUNS), \
            $(SGA) preprocess --pe-mode 1 \
            <(curl $(CICHLID_DIR)/$(id)/$(id)_1.fastq.gz | zcat) \
            <(curl $(CICHLID_DIR)/$(id)/$(id)_2.fastq.gz | zcat) | gzip >> $@;)

human.fastq.gz:
		rm -f $@
		$(foreach id, $(HUMAN_RUNS), \
            $(SGA) preprocess --pe-mode 1 \
                <(curl $(HUMAN_DIR)/$(id)/$(id)_1.fastq.gz | zcat) \
                <(curl $(HUMAN_DIR)/$(id)/$(id)_2.fastq.gz | zcat) | gzip >> $@;)

oyster.fastq.gz:
		rm -f $@
		$(foreach id, $(OYSTER_RUNS), \
            $(SGA) preprocess --pe-mode 1 \
                <(curl $(OYSTER_DIR)/$(id)/$(id)_1.fastq.gz | zcat) \
                <(curl $(OYSTER_DIR)/$(id)/$(id)_2.fastq.gz | zcat) | gzip >> $@;)

yeast.fastq.gz:
		$(SGA) preprocess -s 0.07 --pe-mode 1 \
            <(curl $(YEAST_DIR)/$(YEAST_RUN)/$(YEAST_RUN)_1.fastq.gz | zcat) \
            <(curl $(YEAST_DIR)/$(YEAST_RUN)/$(YEAST_RUN)_2.fastq.gz | zcat) | gzip > $@

# Build the FM-index for each set
%.bwt: %.fastq.gz
		$(SGA) index -a ropebwt -t 8 --no-reverse $<

# Make the preqc file for the short read sets
%.preqc: %.bwt %.fastq.gz
		$(SGA) preqc -t 8 $(patsubst %.bwt, %.fastq.gz, $<) > $@

#
# NA12878 diploid reference
#
NA12878_diploid_dec16.2012.zip:
		wget http://sv.gersteinlab.org/NA12878_diploid/NA12878_diploid_dec16.2012.zip
		unzip $<
		$(SGA) preprocess --permute NA12878_diploid_genome_dec16_2013/*_NA12878_maternal.fa NA12878_diploid_genome_dec16_2013/*_NA12878_paternal.fa > $@

# Build BWT files for the diploid reference
NA12878.diploid.bwt: NA12878.diploid.fa
		$(SGA) index -t 8 -d 4 --no-reverse $<

# Make the reference preqc file
NA12878.diploid.preqc: NA12878.diploid.bwt
		$(SGA) preqc -t 8 --diploid $(patsubst %.bwt, %.fastq.gz, $<) > $@

#
# Simulation
#
diploid.sim.hapcov%.fastq: NA12878.diploid.fa
		$(DWGSIM) -C $* -r 0.0 -1 100 -2 100 -e 0.0001-0.005 -E 0.0001-0.005 -y 0 -d 300 -s 30 $< $@
		rm $@.bwa* $@.mutations.vcf $@.mutations.txt
		mv $@.bfast.fastq $@
        
%.bwt: %.fastq
		$(SGA) index -a ropebwt -t 8 --no-reverse $<

%.preqc: %.bwt %.fastq
		$(SGA) preqc -t 8 $*.fastq > $@

#
# SOAPdenovo2 assemblies
#
%.contigs.fa:
		$(dir $(MAKEFILE_LIST))/run_soap2.pl $@