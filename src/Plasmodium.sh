#!/bin/bash
#This script is intended to demonstrate how bash shell scripting can be used to
#chain UNIX commands together. The workflow downloads the FASTQ file pairs of an
#Illumina Genome Analyser II PAIRED end run from EBI and aligns it against
#a reference genome of Plasmodium falciparum, the deadliest malaria parasite. The
#script depends on samtools and bwa, which can be downloaded and installed
#by running 'make' in this directory.

# where we will download the data
DATA=data/plasmodium
RESULTS_ROOT=results
RESULTS="${RESULTS_ROOT}/"`date | perl -pe 'chomp; s/\s+/\_/g'`

# location of a 282Mb Illumina Genome Analyzer II run, PAIRED, FASTQ
SAMPLEFILE_BASE=ERR022523
SAMPLEURL_BASE=ftp://ftp.sra.ebi.ac.uk/vol1/fastq/ERR022/ERR022523
SAMPLEFILES=""

# location of a Plasmodium falciparum reference genome
REFERENCEFILE=Plasmodium_falciparum_OLD.fna
REFERENCEBASEURL=ftp://ftp.ncbi.nih.gov/genomes/Plasmodium_falciparum_OLD

# alignment file
ALIGNMENTSAIFILES=""
ALIGNMENTBAMFILE="${RESULTS}/aln.bam"
ALIGNMENTBAM="../../${RESULTS}/aln"

# accession numbers in the reference genome. Each is one chromosome.
ACCESSIONS="NC_004325 NC_000910 NC_000521 NC_004318 NC_004326 NC_004327 NC_004328 NC_004329 NC_004330 NC_004314 NC_004315 NC_004316 NC_004331 NC_004317"

# location of the tools we will use. it is assumed they can be found on the $PATH.
BWA=`pwd`/bin/bwa/bwa
SAMTOOLS=`pwd`/bin/samtools/samtools
CURL=curl

# make the data directory if it doesn't exist
if [ ! -d $DATA ]; then
	mkdir -p $DATA
fi

# make the results date subdirectory
if [ ! -d $RESULTS ]; then
    mkdir -p $RESULTS
fi

# download Illumina run (Paired FASTQ) of Plasmodium falciparum
for PAIR in 1 2; do
  SAMPLEFILE="${SAMPLEFILE_BASE}_${PAIR}.fastq"
  ALIGNMENTFILE="${SAMPLEFILE_BASE}_${PAIR}.sai"
  SAMPLEURL="${SAMPLEURL_BASE}/${SAMPLEFILE}.gz"
  if [ ! -e "${DATA}/${SAMPLEFILE}" ]; then
    echo "${CURL} ${SAMPLEURL} | gunzip > ${SAMPLEFILE}"
	cd $DATA
	$CURL $SAMPLEURL | gunzip > $SAMPLEFILE
	cd -
  fi

  if [ -z $ALIGNMENTSAIFILES ]; then
    ALIGNMENTSAIFILES=$ALIGNMENTFILE
  else
    ALIGNMENTSAIFILES="${ALIGNMENTSAIFILES} ${ALIGNMENTFILE}"
  fi

  if [ -z $SAMPLEFILES ]; then
    SAMPLEFILES=$SAMPLEFILE
  else
    SAMPLEFILES="${SAMPLEFILES} ${SAMPLEFILE}"
  fi

done

# download reference FASTA sequences
if [ ! -e "${DATA}/${REFERENCEFILE}" ]; then
	cd $DATA
	COUNTER=1
	for ACCESSION in $ACCESSIONS; do
		if [ ! -e "${ACCESSION}.fna" ]; then
            # fix the chromosome entries on the reference
            echo "${CURL} ${REFERENCEBASEURL}/CHR${COUNTER}/${ACCESSION}.fna | perl -pi -e 's/^\>gi.*chromosome\s(\d+).*/\>chr$1/g' >> ${REFERENCEFILE}"
			$CURL ${REFERENCEBASEURL}/CHR${COUNTER}/${ACCESSION}.fna | perl -pi -e 's/^\>gi.*chromosome\s(\d+).*/\>chr$1/g' >> ${REFERENCEFILE}
		fi
		COUNTER=$[COUNTER + 1]
	done
	cd -
fi

# do bwa index
if [ ! -e "$DATA/${REFERENCEFILE}.amb" ]; then
    echo "${BWA} index ${REFERENCEFILE}"
	cd $DATA
	$BWA index $REFERENCEFILE
	cd -
fi

# do bwa aln on each PAIR separately
for SAMPLEFILE in $SAMPLEFILES; do
  ALIGNMENTSAI=`echo $SAMPLEFILE | sed 's/fastq/sai/'`
  if [ ! -e "$DATA/$ALIGNMENTSAI" ]; then
	echo "${BWA} aln ${REFERENCEFILE} ${SAMPLEFILE} > ${ALIGNMENTSAI}"
	cd $DATA
	$BWA aln $REFERENCEFILE $SAMPLEFILE > $ALIGNMENTSAI
	cd -
  fi
done

# do bwa sampe on paired alignments to produce a single, sorted Bam file
if [ ! -e "$ALIGNMENTBAMFILE" ]; then
	echo "${BWA} sampe ${REFERENCEFILE} ${ALIGNMENTSAIFILES} ${SAMPLEFILES} | ${SAMTOOLS} view -bS - | ${SAMTOOLS} sort - ${ALIGNMENTBAM}"
	cd $DATA
	$BWA sampe $REFERENCEFILE $ALIGNMENTSAIFILES $SAMPLEFILES | ${SAMTOOLS} view -bS - | $SAMTOOLS sort - $ALIGNMENTBAM
    rm $ALIGNMENTSAIFILES
	cd -
fi
