# LiftoverSummstats
A shell (bash) script for lifting over GWAS summary statistics from hg19 to hg38 or vice-versa. The script makes use of Picard and UCSC FASTA files, and runs some basic checks on the input before attempting liftover. A conda environment file is provided which contains all required software.

## Requirements
### Software
- Picard Tools (https://broadinstitute.github.io/picard/)
- Tabix (https://www.htslib.org/doc/tabix.html)
- Bgzip (https://www.htslib.org/doc/bgzip.html)

### Files
- GRCh37 reference genome (`hg19.fa.gz`)
- GRCh38 reference genome (`hg38.fa.gz`)
- UCSC hg19 to hg38 chain file (`hg19ToHg38.over.chain.gz`)
- UCSC hg38 to hg19 chain file (`hg38ToHg19.over.chain.gz`)

## Installation
### 1. Download this repository
Obtain the files in this repository by typing
```
git clone https://github.com/samuelejones/LiftoverSummstats.git
```
then enter the directory by typing
```
cd LiftoverSummstats
```
and make the bash script executable (give it run permissions) by typing
```
chmod +x liftover_summstats.sh
```

### 2. Install conda LIFTOVER environment
Install the environment using the provided `.yml` file:
```    
conda env create -f environment_LIFTOVER.yml
```
This will create a conda environment called `LIFTOVER`. Test the environment works by running
```
conda activate LIFTOVER
```
and then deactivate by running
```
conda deactivate
```

### 3. Download reference genomes
If not already, change to the LiftoverSummstats directory. Then run the commands
```
wget https://hgdownload.soe.ucsc.edu/goldenPath/hg19/bigZips/hg19.fa.gz
```
and
```
wget https://hgdownload.soe.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz
```
to download the reference genomes to the script's directory. Each file is approximately 1Gb in size.

### 4. Edit the shell script and enter the commands and file locations (if needed)
By default, the script assumes you will be using the `LIFTOVER` conda environment (provided) and that you download the reference genomes (`hg19.fa.gz` and `hg38.fa.gz`) to the same folder as the script. If either of these are not true, edit the `liftover_summstats.sh` script and
- set the `loadcondaenv` and `unloadcondaenv` to the empty string (if not using the conda environment) or change the environment name (if using another environment containing all the required software)
- set the location of the reference genomes in the respective `reffile19` and `reffile38` variables
- set the Picard command in the `picardcmd` variable. If set to the empty string, the script will assume picard can be exected using the command `picard`. If your Picard executable is a .jar file, you can set the `picardcmd` variable to `java -jar /path/to/picard.jar` where `/path/to/` describes the location of the `picard.jar` file.

## Running the script
Run the script with the help flag will print the script's usage:
```
./liftover_summstats.sh --help
```
The script has 7 mandatory flags: `--input`, `--chr`, `--pos`, `--ea`, `--oa`, `--out` and either `--b37tob38` or `--b38to37` (depending on whether you are lifting over from hg19 to hg38 or vice-versa).

An example command will look like
```
./liftover_summstats.sh --input mysummstats.txt.gz --chr CHR --pos POS --ea ALT --oa REF --out mysummstatsnew.txt.gz --b37tob38
```
which will produce at least three files
- `mysummstatsnew.txt.gz`: your output summary stats file with the chromosomes and positions in your new build (GRCh38/hg38 in this case). This file will have exactly the same columns and formatting as the input file, except for the chromosome and position changes.
- `mysummstatsnew_rejected.vcf.gz`: a gzipped VCF file containing all variants that could not be lifted over to the requested build (e.g. because the positions don't exist) with the reason and additional information in columns 7 and 8 of that file
- `mysummstatsnew_liftover_picard.log`: a log file of the picard run, which can be useful for debugging purposes

You can also set the delimiter of your input file, which will save time when running checks on the input file. E.g. if your file's delimiter is " " (a space), then you can add the `--delim SPACE` option. Currently, the script only recognises five delimiters: TAB (`	`), SPACE (` `), COMMA (`,`), SEMICOLON (`;`) and PIPE (`|`).

**WARNING** If any of your column names begin with or contain the comment character `\#`, then you need to both escape the # and surround the string with quotes. E.g. the chromosome column is named `\#chrom`, then your chromosome flag will be `--chr '\#chrom'`. Failing to pass these column names correctly may result in unexpected behaviour and data loss.

## Acknowledgement
If you make use of this script in your project, please acknowledge this GitHub page and the author: Samuel E. Jones, Finnish Institute for Molecular Medicine, University of Helsinki. Please also acknowledge/cite [Picard](https://github.com/broadinstitute/picard#citing) and the [HTSlib/BCFtools authors](https://www.htslib.org/doc/#publications).

## Licence
This script is provided under the GNU General Public Licence v3.
