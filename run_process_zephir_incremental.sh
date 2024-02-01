#!/bin/bash

# Call this script with:
# - exactly one date argument of the form YYYYMMDD
# OR
# - no arguments to use yesterday's date

if [[ $# -eq 0 ]]; then
  YESTERDAY=`date --date="yesterday" +%Y%m%d`
else
  if [[ "$1" =~ ^[0-9]{8}$ ]]; then
    YESTERDAY=$1
  else
    echo "Invalid date format '$1', need YYYYMMDD"
    exit 1
  fi
fi

source $ROOTDIR/config/defaults
cd $TMPDIR

SCRIPTNAME=`basename $0`
zephir_date="$(echo $YESTERDAY | sed 's/\(....\)\(..\)/\1-\2-/')"

# Route all external processes through these functions
# to avoid silent failures.
function run_external_command {
  $1
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="`date`: error: '$1' returned $cmdstatus"
    report_error_and_exit "$message"
  fi
}

function report_error_and_exit {
  echo $1
  echo $1 | mailx -s"error in $SCRIPTNAME" $EMAIL
  exit 1
}

export us_fed_pub_exception_file="$FEDDOCS_HOME/feddocs_oclc_filter/oclcs_removed_from_registry.txt"

DATADIR=$ROOTDIR/data/zephir
ZEPHIR_VUFIND_EXPORT=ht_bib_export_incr_${zephir_date}.json.gz 
ZEPHIR_VUFIND_DELETE=vufind_removed_cids_${zephir_date}.txt.gz
ZEPHIR_GROOVE_INCREMENTAL=groove_incremental_${zephir_date}.tsv.gz
ZEPHIR_DAILY_TOUCHED=daily_touched_${zephir_date}.tsv.gz
ZEPHIR_VUFIND_DOLL_D=vufind_incremental_${zephir_date}_dollar_dup.txt
BASENAME=zephir_upd_${YESTERDAY}
REPORT_FILE=${BASENAME}_report.txt

echo "starting: `date`"
echo "basename is $BASENAME"
echo "fed pub exception file set in environment: $us_fed_pub_exception_file"

echo "`date`: zephir incremental extract started"
echo "`date`: retrieve $ZEPHIR_VUFIND_EXPORT"

run_external_command "$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_VUFIND_EXPORT"

if [ ! -e $ZEPHIR_VUFIND_EXPORT ]; then
  report_error_and_exit "file $ZEPHIR_VUFIND_EXPORT not found, exiting"
fi

echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE"

run_external_command "$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_DELETE $ZEPHIR_VUFIND_DELETE"

if [ ! -e $ZEPHIR_VUFIND_DELETE ]; then
  report_error_and_exit "file $ZEPHIR_VUFIND_DELETE not found, exiting"
fi

echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL"

run_external_command "$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_INCREMENTAL $ZEPHIR_GROOVE_INCREMENTAL"

cmdstatus=$?
if [ $cmdstatus == "0" ]; then
  echo "`date`: copy $ZEPHIR_GROOVE_INCREMENTAL to rootdir/data/zephir"
  # should go here:
  mv $ZEPHIR_GROOVE_INCREMENTAL $INGEST_BIBRECORDS
else
  echo "***"
  echo "Problem getting file ${ZEPHIR_GROOVE_INCREMENTAL} from zephir: rc is $cmdstatus"
  echo "***"
fi

echo "`date`: retrieve $ZEPHIR_DAILY_TOUCHED"

$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_DAILY_TOUCHED $ZEPHIR_DAILY_TOUCHED

cmdstatus=$?
if [ $cmdstatus == "0" ]; then
  echo "`date`: copy $ZEPHIR_DAILY_TOUCHED to $INGEST_BIBRECORDS"
  mv $ZEPHIR_DAILY_TOUCHED $INGEST_BIBRECORDS
else 
  echo "***"
  echo "Problem getting file ${ZEPHIR_DAILY_TOUCHED} from zephir: rc is $cmdstatus"
  echo "***"
fi

echo "`date`: dump the rights db to a dbm file"

run_external_command "$ROOTDIR/bld_rights_db.pl -x $RIGHTS_DBM"

echo "`date`: processing file $ZEPHIR_VUFIND_EXPORT"
cmd="JOB_NAME=run_process_zephir_incremental.sh $ROOTDIR/postZephir.pm -i $ZEPHIR_VUFIND_EXPORT -o $BASENAME -r ${BASENAME}.rights -d -f $RIGHTS_DBM > ${BASENAME}_stderr"
run_external_command "$cmd"
tail -50 ${BASENAME}_rpt.txt

run_external_command "zcat $ZEPHIR_VUFIND_DELETE > ${BASENAME}_zephir_delete.txt"
run_external_command "sort -u ${BASENAME}_zephir_delete.txt ${BASENAME}_delete.txt -o ${BASENAME}_all_delete.txt"
run_external_command "gzip ${BASENAME}_all_delete.txt"

echo "`date`: move rights file ${BASENAME}.rights to $RIGHTS_DIR"
run_external_command "mv ${BASENAME}.rights $RIGHTS_DIR"

echo "`date`: compress json file and send to hathitrust solr server"
run_external_command "gzip -n -f ${BASENAME}.json"

run_external_command "cp ${BASENAME}.json.gz $CATALOG_PREP"

# copy to ht archive directory
run_external_command "cp ${BASENAME}.json.gz $CATALOG_ARCHIVE"

echo "`date`: send combined delete file to hathitrust solr server as ${BASENAME}_delete.txt.gz"

run_external_command "mv ${BASENAME}_all_delete.txt.gz $CATALOG_PREP/${BASENAME}_delete.txt.gz"

echo "`date`: compress dollar dup files and send to zephir"
run_external_command "mv ${BASENAME}_dollar_dup.txt $ZEPHIR_VUFIND_DOLL_D"
run_external_command "gzip -n -f $ZEPHIR_VUFIND_DOLL_D"
run_external_command "$ROOTDIR/ftpslib/ftps_zephir_send ${ZEPHIR_VUFIND_DOLL_D}.gz"

# This should have already been copied to the archive/catalog
rm ${BASENAME}.json.gz

echo "DONE `date`"
# TODO run cleanup_directory.sh?

# echo "copy rights debug file to mdp_govdocs directory"
# todo: why? what uses debug_current?
# cat ${BASENAME}.rights.debug >> $ROOTDIR/data/zephir/debug_current.txt
exit
