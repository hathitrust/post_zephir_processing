#!/bin/bash

# Route all external processes through these functions
# to avoid silent failures.
function run_external_command {
  eval "$@"
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="`date`: error: '$@' returned $cmdstatus"
    report_error_and_exit "$message"
  fi
}

function report_error_and_exit {
  echo "**"
  echo "$1"
  echo "**"
  echo "$1" | mailx -s"error in $SCRIPTNAME" $EMAIL
  exit 1
}

source $ROOTDIR/config/defaults
cd $TMPDIR

echo "starting: `date` in $TMPDIR with data in $DATA_ROOT"

SCRIPTNAME=`basename $0`
zephir_date=`date --date="yesterday" +%Y-%m-%d`
YESTERDAY=`date --date="yesterday" +%Y%m%d`
TODAY=`date +%Y%m%d`

today_dash=`date +%Y-%m-%d`
us_fed_pub_exception_file=$FEDDOCS_HOME/feddocs_oclc_filter/oclcs_removed_from_registry.txt
echo "fed pub exception file set in environment: $us_fed_pub_exception_file"

# File from zephir contains ~9 million records as of 2022
SPLITCOUNT=1000000

ZEPHIR_VUFIND_EXPORT=ht_bib_export_full_${zephir_date}.json.gz
ZEPHIR_GROOVE_EXPORT=groove_export_${zephir_date}.tsv.gz

echo "basename is zephir_full_monthly"

echo "`date`: zephir full extract started"

echo "`date`: retrieve zephir files: groove_export_${zephir_date}.tsv.gz"

run_external_command $ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_EXPORT $ZEPHIR_GROOVE_EXPORT
if [ ! -e $ZEPHIR_GROOVE_EXPORT ]; then
  report_error_and_exit "file $ZEPHIR_GROOVE_EXPORT not found, exiting" 
fi

run_external_command mv $ZEPHIR_GROOVE_EXPORT $INGEST_BIBRECORDS/groove_full.tsv.gz

echo "*** retrieve full zephir vufind extract" 

run_external_command $ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT
if [ ! -e $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT ]; then
  report_error_and_exit "file $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT not found, exiting" 
fi

echo "*** dump the rights db to a dbm file" 
run_external_command $ROOTDIR/bld_rights_db.pl -x $RIGHTS_DBM

# split the json file 
rm -f zephir_full_monthly_??
echo "input file is $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT"
ls -l $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT

run_external_command "unpigz -c $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT | split -l $SPLITCOUNT - zephir_full_monthly_"

file_list=`ls zephir_full_monthly_??`

for file in $file_list; do
  echo "`date`: processing file $file"
  # TODO: wait to finalize until all of these have run?
  cmd = "JOB_APP=run_zephir_full_monthly JOB_NAME=\"$file\" $ROOTDIR/postZephir.pm -z 1 -i $file -o ${file}_out -r ${file}.rights -d -f $RIGHTS_DBM &> ${file}_stderr &"
  run_external_command $cmd
done

# wait loop: check last line of each rpt file
# exit from loop when all are done (last line eq "DONE")
echo "`date`: wait for post_zephir_cleanup processes to end" 
while :
do
  #echo "`date` sleeping......"
  sleep 60
  alldone=true
  for file in $file_list; do
    rpt=${file}_stderr
    last_line=`tail -1 $rpt`
    if [ "$last_line" != "DONE" ]; then
      #echo "last line from $rpt is $last_line"
      alldone=false
    fi
  done
  if $alldone; then
    break
  fi
done

echo "`date`: all files processed, concatenate and compress files to zephir_ingested_items.txt.gz" 
run_external_command "cat zephir_full_monthly_??_out_zia.txt | pigz -c > zephir_ingested_items.txt.gz"

echo "`zcat zephir_ingested_items.txt.gz | wc -l` lines in zephir ingested items file" 
run_external_command mv zephir_ingested_items.txt.gz $INGEST_BIBRECORDS

echo "Prepare and deliver monthly output" 

echo "`date`: all files processed, concatenate and compress vufind json files to zephir_full_${YESTERDAY}_vufind.json.gz" 
run_external_command "cat zephir_full_monthly_??_out.json | pigz -c > zephir_full_${YESTERDAY}_vufind.json.gz"

echo "`date`: sending full file to hathi trust catalog solr server" 
run_external_command cp zephir_full_${YESTERDAY}_vufind.json.gz $CATALOG_PREP

echo "`date`: mv full file to catalog archive" 
run_external_command mv zephir_full_${YESTERDAY}_vufind.json.gz $CATALOG_ARCHIVE

echo "`date`: all files processed, concatenate rights files to zephir_full_${YESTERDAY}.rights" 
run_external_command cat zephir_full_monthly_??.rights > zephir_full_${YESTERDAY}.rights

run_external_command mv zephir_full_${YESTERDAY}.rights $RIGHTS_DIR

echo "`date`: all files processed, concatenate rights debug files to zephir_full_${YESTERDAY}.rights.debug" 
run_external_command cat zephir_full_monthly_??.rights.debug > zephir_full_${YESTERDAY}.rights.debug

echo "`date`: all files processed, concatenate rights chg files to zephir_full_${YESTERDAY}.rights.tsv" 
run_external_command sort -u zephir_full_monthly_??.rights_rpt.tsv -o zephir_full_${YESTERDAY}.rights_rpt.tsv

run_external_command mv zephir_full_${YESTERDAY}.rights_rpt.tsv $ZEPHIR_DATA/full/

echo "`date`: all files processed, concatenate report files to zephir_full_monthly_rpt.txt" 
run_external_command cat zephir_full_monthly_??_out_rpt.txt > zephir_full_monthly_rpt.txt

run_external_command mv zephir_full_monthly_rpt.txt $ZEPHIR_DATA/full/

echo "`date`: cleanup--counts" 
zephir_count=`unpigz -c $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT | wc -l`
hathi_catalog_count=`unpigz -c $CATALOG_ARCHIVE/zephir_full_${YESTERDAY}_vufind.json.gz | wc -l`
echo "`date`: $zephir_count records in full zephir export json file" 
echo "`date`: $hathi_catalog_count records in full hathi catalog json file" 
echo 

echo "`date`: cleanup--remove intermediate files" 
cat zephir_full_monthly_*stderr > stderr.tmp.txt
rm zephir_full_monthly_??
rm zephir_full_monthly_??_*
rm zephir_full_monthly_??.*

# TODO run cleanup_directory.sh?
  
echo "`date`: DONE" 
exit
