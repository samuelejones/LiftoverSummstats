# get script name
scriptname="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
scriptdir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
blank=${scriptname//?/ }

# store number of input args
nargs=$#

# echo empty line
echo

##################################
### SET LOCATIONS AND COMMANDS ###
##################################

## command for loading LIFTOVER env (if needed)
loadcondaenv="conda activate LIFTOVER" # set as empty string ("") if no conda env needed
unloadcondaenv="conda deactivate"  # set as empty string ("") if no conda env needed

## locations of chain and fasta files
chainfile19to38="$scriptdir/hg19ToHg38.over.chain.gz" # chain file hg19 to hg38
reffile38="$scriptdir/hg38.fa.gz" # hg38 fasta file
chainfile38to19="$scriptdir/hg38ToHg19.over.chain.gz" # chain file hg38 to hg19
reffile19="$scriptdir/hg19.fa.gz" # hg19 fasta file

## location of picard (if needed - not needed if LIFTOVER conda env loaded)
picardcmd="" # set as empty string ("") if conda env loaded or picard executable is in $PATH
#picardcmd="java -jar /apps/genetics/picard/picard.jar" # set as empty string ("") if conda env loaded or picard executable is in $PATH

#############
### USAGE ###
#############

usage()
{
   # Display Help
   echo -e "   This script takes an input summary statistics file and performs a liftover with picard."
   echo -e "   The resulting output file will contain the same columns but with chromosome and position"
   echo -e "   in the requested build. The script currently only lifts from b37 to b38 or vice-versa."
   echo
   echo -e "   Usage: $scriptname --input INPUTFILE --chr CHRCOL --pos POSCOL --ea EACOL"
   echo -e "          $blank --oa OACOL --out OUTPUTFILE [--b37to38] [--b38to37]"
   echo -e "          $blank [--delim DELIM] [--help]"
   echo
   echo -e "   Options [REQ=Required; OPT=Optional]:"
   echo
   echo -e "   --input INPUTFILE         Relative/absolute path of file to be standardised [REQ]"
   echo -e "   --chr CHRCOL              Name of chromosome column [REQ]"
   echo -e "   --pos POSCOL              Name of chromosomal position column [REQ]"
   echo -e "   --ea EACOL                Name of effect allele column [REQ]"
   echo -e "   --oa OACOL                Name of non-effect (other) allele column [REQ]"
   echo
   echo -e "                             If any columns are prefixed with #, enclose the column name"
   echo -e "                             name in single quotes and add a backslash (\"\\\") before the #"
   echo
   echo -e "   --out OUTPUTFILE          Relative/absolute path of output file [REQ]"
   echo -e "                             If OUTPUTFILE doesn't have gz extension, it is added"
   echo -e "   --b37to38                 Lift b37/hg19 to b38 [OPT]"
   echo -e "   --b38to37                 Lift b38 to b37/hg19 [OPT]"
   echo -e "                             User must specify exactly one of --b37to38 or --b38to37."
   echo
   echo -e "   --delim DELIM             Name of delimiter separating input file columns [OPT]"
   echo -e "                             Valid options are TAB, SPACE, COMMA, SEMICOLON, PIPE"
   echo -e "   --help                    Display usage and exit [OPT]"
   echo
   exit $1
}


###################################
### LOGGING AND PRINT FUNCTIONS ###
###################################

__log_init__() {
    if [[ -t 1 ]]; then
        # colors for logging in interactive mode
        [[ $COLOR_BOLD ]]   || COLOR_BOLD="\033[1m"
        [[ $COLOR_RED ]]    || COLOR_RED="\033[0;31m"
        [[ $COLOR_GREEN ]]  || COLOR_GREEN="\033[0;34m"
        [[ $COLOR_YELLOW ]] || COLOR_YELLOW="\033[0;33m"
        [[ $COLOR_BLUE ]]   || COLOR_BLUE="\033[0;32m"
        [[ $COLOR_OFF ]]    || COLOR_OFF="\033[0m"
    else
        # no colors to be used if non-interactive
        COLOR_RED= COLOR_GREEN= COLOR_YELLOW= COLOR_BLUE= COLOR_OFF=
    fi
    readonly COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_OFF

    #
    # map log level strings (FATAL, ERROR, etc.) to numeric values
    #
    # Note the '-g' option passed to declare - it is essential
    #
    unset _log_levels _loggers_level_map
    declare -gA _log_levels _loggers_level_map
    _log_levels=([FATAL]=0 [ERROR]=1 [WARN]=2 [INFO]=3 [DEBUG]=4 [VERBOSE]=5)

}

# set spaces to pad out subsequent lines printed by "print_" commands
sp11="           "

# print commands
print_error() {
    {
        printf "${COLOR_RED}ERROR ::   "
        printf '%s\n' "$1"
        [ "$#" -gt "1" ] && { shift; printf "${sp11}%s\n" "$@"; }
        printf "$COLOR_OFF\n"
    } >&2
    exit 1
}

print_warn() {
    printf "${COLOR_YELLOW}WARNING :: "
    printf '%s\n' "$1"
    [ "$#" -gt "1" ] && { shift; printf "${sp11}%s\n" "$@"; }
    printf "$COLOR_OFF"
}

print_info() {
    printf "${COLOR_BLUE}INFO ::    "
    printf '%s\n' "$1"
    [ "$#" -gt "1" ] && { shift; printf "${sp11}%s\n" "$@"; }
    printf "$COLOR_OFF"
}

print_info_list() {
    printf "${COLOR_BLUE}INFO ::    "
    printf '%s\n' "$1"
    [ "$#" -gt "1" ] && { shift; printf "${sp11} -> %s\n" "$@"; }
    printf "$COLOR_OFF"
}


# print only if output is going to terminal
print_tty() {
    if [[ -t 1 ]]; then
        printf "${sp11}%s\n" "$@"
    fi
}

#######################
###                 ###
### CHECK ARGUMENTS ###
###                 ###
#######################

# if no arguments passed, display usage and exit with code 1
if [[ ! $@ =~ ^\-.+ ]]
then
   print_error "No options or arguments. Run \"./$scriptname --help\" to see usage."
fi

# define function to catch badly parsed arguments
catch_badargs() {
   [[ $1 =~ --* ]] && print_error "Missing argument for \"$2\" option."
   [[ -z "${1// }" ]] && print_error "Missing argument for \"$2\" option."
}

# set build flags to FALSE
b37to38=false
b38to37=false

# process arguments
opts="$@"
eval set -- "$opts"

while (( "$#" )); do
    case "$1" in
    --help)
        usage 0
        ;;
    --input)  
        shift
        inputfile=$1 && catch_badargs "$inputfile" '--input'
        ;;
    --chr)  
        shift
        chrcol=$1 && catch_badargs "$chrcol" '--chr'
        ;;
    --pos)  
        shift
        poscol=$1 && catch_badargs "$poscol" '--pos'
        ;;
    --ea)
        shift
        eacol=$1 && catch_badargs "$eacol" '--ea'
        ;;
    --oa)
        shift
        oacol=$1 && catch_badargs "$oacol" '--oa'
        ;;
    --out)
        shift
        outputfile=$1 && catch_badargs "$outputfile" '--out'
        ;;
    --delim)
        shift
        delimiter=$1 && catch_badargs "$delimiter" '--delim'
        ;;
    --b37to38)
        b37to38=true
        ;;
    --b38to37)
        b38to37=true
        ;;
    *) # unrecognised option
        print_error "Invalid option \"$1\" detected." "Run \"./$scriptname --help\" to see usage"
        ;;
    esac
    shift
done


######################
### INPUT CHECKING ###
######################

### check all required fields present
reqarg=("input" "chr" "pos" "ea" "oa" "out")
reqvar=("inputfile" "chrcol" "poscol" "eacol" "oacol" "outputfile")

for reqi in ${!reqarg[@]}
do
   [ -z "${!reqvar[$reqi]}" ] && print_error "Missing required option \"--${reqarg[$reqi]}\""
   [[ "${!reqvar[$reqi]}" =~ --* ]] && print_error "Missing argument for option \"--${reqarg[$reqi]}\""
done

### check whether build flags have been specified
if [ "$b37to38" = "true" ] && [ "$b38to37" = "true" ]
then
   print_error "Both --b37to38 and --b38to37 specified." "Please specify at most one build."
elif [ "$b37to38" = "true" ]
then
   print_info "Liftover will convert b37/hg19 input to b38"
elif [ "$b38to37" = "true" ]
then
   print_info "Liftover will convert b38 input to b37/hg19"
else
   print_error "Please specify either --b37to38 or --b38to37."
fi

### check chain and fasta file paths given and files exist and have size>0
[ -z "$chainfile19to38" ] && print_error "Please specify location of hg19 to hg38 chain file."
[ -s "$chainfile19to38" ] || print_error "Chain file (\"$chainfile19to38\") for hg19 to hg38 does not exist or is empty."
[ -z "$chainfile38to19" ] && print_error "Please specify location of hg38 to hg19 chain file."
[ -s "$chainfile38to19" ] || print_error "Chain file (\"$chainfile38to19\") for hg38 to hg19 does not exist or is empty."
[ -z "$reffile38" ] && print_error "Please specify location of hg38 reference FASTA file."
[ -s "$reffile38" ] || print_error "Reference FASTA file (\"$reffile38\") for hg38 does not exist or is empty."
[ -z "$reffile19" ] && print_error "Please specify location of hg19 reference FASTA file."
[ -s "$reffile19" ] || print_error "Reference FASTA file (\"$reffile19\") for hg19 does not exist or is empty."

# input file exist and >0 size
if [ -z "${inputfile}" ]
then
   print_error "No valid filename given for --input option"
elif [ ! -s "${inputfile}" ]
then
   print_error "Input file \"$inputfile\" does not exist or is empty"
fi

# check write permissions in output file dir
outdir=`dirname "${outputfile}"`
[ -d "$outdir" ] || print_error "Directory for output file does not exist"
[ -w "$outdir" ] || print_error "Directory for output file is not writeable"

# input file is compressed or not
if (file "${inputfile}" | grep -q compressed )
then
   catcmd=zcat
else
   catcmd=cat
fi
# define cat function that will use catcmd and convert DOS line endings on the fly
function catfun () { $catcmd $1 | sed $'s/\r$//'; }


# error if input file has less than 2 lines
if [[ `catfun "${inputfile}" | head | wc -l` -lt 2 ]]
then
   print_error "Input summary stats file should contain at least two lines"
fi

# test delimiter choice is one of the allowed options
# (TAB, SPACE, COMMA, SEMICOLON, PIPE)

# if delimiter set
if [ ! -z ${delimiter+x} ]
then
   # test it is valid
   if [[ "$delimiter" =~ ^(TAB|SPACE|COMMA|SEMICOLON|PIPE)$ ]]
   then
      # report set delimiter
      print_info "Delimiter set as $delimiter"
      # test that delimiter is correct by checking how many unique field counts file has in first 100 lines
      nuniq=`awk -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim]}{print NF}' <( catfun "${inputfile}" | head -n 100) | sort | uniq -c | wc -l`
      # if >1, then delimiter may be incorrect
      [ "$nuniq" -gt "1" ] && print_error "Input file is not regular or wrong delimiter specified"
      # count number of fields in first 100 lines
      nfields=`awk -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim]}{print NF}' <( catfun "${inputfile}" | head -n 100) | sort | uniq -c | awk '{print $1}'`
      if [ "$nfields" -eq "1" ]
      then
         print_error "To few fields detected using specified delimiter"
      fi
   else
      print_error "Unrecognised delimiter \"$delimeter\": please see usage"
   fi
else
   # otherwise, try to find delimiter
   nfieldscur=1
   delimcur=""
   for delimiter in TAB SPACE COMMA SEMICOLON PIPE
   do
      nfields=0
      nuniq=`awk -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim]}{print NF}' <( catfun "${inputfile}" | head -n 100) | sort | uniq -c | wc -l`
      if [ "$nuniq" -eq "1" ]
      then
         nfields=`awk -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim]}{print NF}' <( catfun "${inputfile}" | head -n 100) | sort | uniq -c | awk '{print $2}'`
         if [ "$nfields" -gt "$nfieldscur" ]
         then
            nfieldscur=$nfields
            delimcur=$delimiter
         fi
      fi
   done
   # check if delimiter detected (delimcur!="") and exit if failed
   if [ -z "$delimcur" ]
   then
      print_error "Unable to detect delimiter as one of: TAB SPACE COMMA SEMICOLON PIPE"
   else
      print_info "Delimiter automatically detected as \"$delimcur\""
      delimiter=$delimcur
   fi
fi

### check all columns exist (including extra and info cols if set)
# set string containing all columns
reqcols=("chrcol" "poscol" "eacol" "oacol")
allcols=`for col in ${reqcols[@]}; do echo ${!col}; done; [ ! -z "$extracols" ] && echo "$extracols" | sed 's/,/\n/g'; [ ! -z "$infocol" ] && echo "$infocol"`
# test that all these columns exist using specified or detected delimiter
missingcols=`awk -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim]}NR==FNR{a[$1]++;next}{for(i=1;i<=NF;i++){if($i in a){delete a[$i]}};for(key in a){print key};exit}' <(for col in $allcols; do echo $col; done) <( catfun "${inputfile}")`
[ ! -z "$missingcols" ] && print_error "Input file is missing the following specified columns:" "$missingcols"

####
### check columns contain correct data type
print_info "Checking input file columns for correct data types"
# chr  - can be numeric (1-26) or character (X, XY, Y, MT)
#        can be prefixed with "chr"
# pos  - can be numeric (positive integer with max value 3E9)
# ea   - can consist of A, C, G or T
# oa   - can consist of A, C, G or T
incheck=`catfun "$inputfile" | awk -v chrcol=$chrcol -v poscol=$poscol -v eacol=$eacol -v oacol=$oacol -v delim=$delimiter -v randno=$randno 'function nn(x){split(x,xx,"");str=xx[1];for(i=2;i<=length(xx);i++){str=str""n[xx[i]]};return str}BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim];n["A"]=1;n["C"]=2;n["G"]=3;n["T"]=4;for(i=1;i<=22;i++){chr[i]=i};chr[23]="X";chr[24]="Y";chr[25]="X";chr[26]="MT";chr["X"]="X";chr["XY"]="X";chr["Y"]="Y";chr["MT"]="MT";chr["M"]="MT"}NR==1{for(i=1;i<=NF;i++){cn[$i]=i};next}{cc=$cn[chrcol];gsub("chr","",cc);if(cc~/^[0-9]+$/){cc=cc+0}}!(cc in chr){print "CHR__"cc"__"NR;ex++;exit}$cn[poscol]<0||$cn[poscol]>3E9||$cn[poscol]!~/(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+\-]?\d+)?/{print "POS__"$cn[poscol]"__"NR;ex++;exit}$cn[eacol]!~/^[ACDGIT]+$/{print "EA__"$cn[eacol]"__"NR;ex++;exit}$cn[oacol]!~/^[ACDGIT]+$/{print "OA__"$cn[oacol]"__"NR;ex++;exit}{cpra=chr[cc]":"$cn[poscol]":"$cn[eacol]":"$cn[oacol]}nn($cn[oacol])<nn($cn[eacol]){cpra=chr[cc]":"$cn[poscol]":"$cn[oacol]":"$cn[eacol]}{print cpra >> ".varlist_chr"chr[cc]"."randno".tmp"}!(chr[cc] in chrlist){chrlist[chr[cc]]++;print chr[cc] >> ".chrlist."randno".tmp"}{nf[NF]++}END{if(!ex){if(length(nf)>1){modenfc=0;for(nfk in nf){if(nf[nfk]>modenfc){modenfc=nf[nfk];modenf=nfk}};print "NUMF__"modenf"__"length(nf)}else{print "DONE"}}}'`


# if "DONE" - file passes checks
# otherwise, print error message
ica=(${incheck//__/ })
case "${ica[0]}" in
   DONE)
      print_info "Input summary columns contain correct data types"
      ;;
   NUMF)
      rm -f .varlist_chr*.${randno}.tmp .chrlist.${randno}.tmp
      print_error "Input file contains lines with unequal column counts" "Modal number of fields are ${ica[1]}, with ${ica[2]} different field counts detected."
      ;;
   *)
      [ "${ica[0]}" = "CHR" ] && msg_str="chromosome code"
      [ "${ica[0]}" = "POS" ] && msg_str="position"
      [ "${ica[0]}" = "EA" ] && msg_str="effect allele"
      [ "${ica[0]}" = "OA" ] && msg_str="alt allele"
      rm -f .varlist_chr*.${randno}.tmp .chrlist.${randno}.tmp
      print_error "Incorrect ${msg_str} \"${ica[1]}\" on line ${ica[2]} of input file"
      ;;
esac


### add .gz extension to output file if missing and name temporary VCF files
[[ "$outputfile" == *.gz ]] || outputfile="$outputfile.gz"
vcfprename=`echo $outputfile | sed 's/\.gz/_prelift\.vcf\.gz/g'`
vcfpostname=`echo $outputfile | sed 's/\.gz/_postlift\.vcf\.gz/g'`
vcfrejname=`echo $outputfile | sed 's/\.gz/_rejected\.vcf\.gz/g'`
liftlogname=`echo $outputfile | sed 's/\.gz/_liftover_picard\.log/g'`

### CONVERT TO VCF FORMAT
print_info "Converting input file to VCF format"
# activate LIFTOVER conda env (if installed)
[ -z "$loadcondaenv" ] || $loadcondaenv
# create input VCF
{
   fd=$(date +'%Y%m%d')
   echo "##fileformat=VCFv4.0"
   echo "##filedate=$fd"
   echo -e "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"
   catfun "$inputfile" | awk -v chrcol=$chrcol -v poscol=$poscol -v eacol=$eacol -v oacol=$oacol -v delim=$delimiter -v fd=$(date +'%Y%m%d') 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS=d[delim];n["A"]=1;n["C"]=2;n["D"]=3;n["G"]=4;n["I"]=5;n["T"]=6;for(i=1;i<=23;i++){chrom[i]=i};chrom["X"]=23;chrom["Y"]=24;chrom["M"]=25}NR==1{for(i=1;i<=NF;i++){cn[$i]=i};next}{cc=$cn[chrcol];gsub("chr","",cc);if(cc~/^[0-9]+$/){cc=cc+0};if(cc==23||cc==25){cc="X"}else if(cc==24){cc="Y"}else if(cc==26){cc="M"};vn=NR-1}{print cc"\t"$cn[poscol]"\t"vn"\t"$cn[oacol]"\t"$cn[eacol]"\t.\t.\t.\t"chrom[cc]}' | sort -nk9 -k2 | cut -f1-8 | awk '{print "chr"$0}'
} | bgzip > $vcfprename 
# index input VCF
tabix -s 1 -b 2 -e 2 $vcfprename


### LIFTOVER CONVERTED VCF
if [ "$b37to38" = "true" ]
then
   # b37/hg19 to b38
   print_info "Performing liftover from b37/hg19 to b38"
   # set chain and reference files
   chainfile="$chainfile19to38"
   reffile="$reffile38"
elif [ "$b38to37" = "true" ]
then
   print_info "Performing liftover from b38 to b37/hg19"
   # set chain and reference files
   chainfile="$chainfile38to19"
   reffile="$reffile19"
fi

# liftover step - send output to log file
[ -z "$picardjar" ] && $picardjar="picard"
{
   java -jar $picardjar LiftoverVcf \
      -I $vcfprename \
      -O $vcfpostname \
      --CHAIN $chainfile \
      --REJECT $vcfrejname \
      -R $reffile \
      --MAX_RECORDS_IN_RAM 500000 \
      --RECOVER_SWAPPED_REF_ALT true
} > $liftlogname 2>&1 || { rm -f $vcfprename $vcfprename.tbi $vcfpostname $vcfpostname.tbi; print_error "LiftOver failed - see \"$liftlogname\" for details"; }

### CONVERT BACK TO ORIGINAL FORMAT
print_info "Updating positions in input file to new build"
{
   catfun "$inputfile" | head -n 1 
   awk -v chrcol=$chrcol -v poscol=$poscol -v eacol=$eacol -v oacol=$oacol -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";for(i=1;i<=22;i++){chrom[i]=i};chrom["X"]=23;chrom["Y"]=24;chrom["M"]=26}NR==FNR{if($0~/^#/){next};cc=$1;gsub("chr","",cc);if(!(cc in chrom)){next};cp[$3]=cc":"$2;next}FNR==1{FS=d[delim];OFS="\t";for(i=1;i<=NF;i++){cn[$i]=i};next}{vn=FNR-1}(vn in cp){split(cp[vn],a,":");chr=a[1];gsub("chr","",chr);$cn[chrcol]=chr;$cn[poscol]=a[2];print chrom[chr]"\t"$0}' <(zcat $vcfpostname) <(catfun "$inputfile") | sort -nk1 -k3 | cut -f2- | awk -v delim=$delimiter 'BEGIN{d["TAB"]="\t";d["SPACE"]=" ";d["COMMA"]=",";d["SEMICOLON"]=";";d["PIPE"]="|";FS="\t";OFS=d[delim]}NR==1{next}{$1=$1;print}'
} | gzip --best > $outputfile


### CLEAN UP
print_info "Cleaning up temporary files"
[ -z "$unloadcondaenv" ] || $unloadcondaenv # unload conda env if loaded
rm -f $vcfprename $vcfprename.tbi $vcfpostname $vcfpostname.tbi

echo
