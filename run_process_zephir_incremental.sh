#!/bin/bash

source $ROOTDIR/config/defaults
cd $TMPDIR

SCRIPTNAME=`basename $0`
zephir_date=`date --date="yesterday" +%Y-%m-%d`
YESTERDAY=`date --date="yesterday" +%Y%m%d`
TODAY=`date +%Y%m%d`
today_dash=`date +%Y-%m-%d`

export us_fed_pub_exception_file="$FEDDOCS_HOME/feddocs_oclc_filter/oclcs_removed_from_registry_${today_dash}.txt"

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

$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_VUFIND_EXPORT

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem getting file ${ZEPHIR_VUFIND_EXPORT} from zephir: rc is $cmdstatus"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" $EMAIL 
fi

if [ ! -e $ZEPHIR_VUFIND_EXPORT ]; then
  message="file $ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" $EMAIL
  exit
fi

echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE"

$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_DELETE $ZEPHIR_VUFIND_DELETE

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem getting file ${ZEPHIR_VUFIND_DELETE} from zephir: rc is $cmdstatus"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" $EMAIL
  exit
fi

if [ ! -e $ZEPHIR_VUFIND_DELETE ]; then
  message="file $ZEPHIR_VUFIND_DELETE not found, exitting"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" $EMAIL
  exit
fi

echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL"

$ROOTDIR/ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_INCREMENTAL $ZEPHIR_GROOVE_INCREMENTAL

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
$ROOTDIR/bld_rights_db.pl -x $RIGHTS_DBM

echo "`date`: processing file $ZEPHIR_VUFIND_EXPORT"
$ROOTDIR/postZephir.pm -i $ZEPHIR_VUFIND_EXPORT -o ${BASENAME} -r ${BASENAME}.rights -d -f $RIGHTS_DBM > ${BASENAME}_stderr 
tail -50 ${BASENAME}_rpt.txt

zcat $ZEPHIR_VUFIND_DELETE > ${BASENAME}_zephir_delete.txt
sort -u ${BASENAME}_zephir_delete.txt ${BASENAME}_delete.txt -o ${BASENAME}_all_delete.txt
gzip ${BASENAME}_all_delete.txt

echo "`date`: copy rights file ${BASENAME}.rights to $RIGHTS_DIR"
mv ${BASENAME}.rights $RIGHTS_DIR

echo "`date`: compress json file and send to hathitrust solr server"
gzip -n -f ${BASENAME}.json

cp ${BASENAME}.json.gz $CATALOG_PREP
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem transferring file ${BASENAME}.json.gz to $CATALOG_PREP: rc is $cmdstatus"
  echo $message
  exit
fi

# copy to ht archive directory
cp ${BASENAME}.json.gz  ${CATALOG_ARCHIVE}

echo "`date`: send combined delete file to hathitrust solr server as ${BASENAME}_delete.txt.gz"

mv ${BASENAME}_all_delete.txt.gz $CATALOG_PREP/${BASENAME}_delete.txt.gz
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem transferring file $ZEPHIR_VUFIND_DELETE to $CATALOG_PREP: rc is $cmdstatus"
  echo $message
  exit
fi

echo "`date`: compress dollar dup files and send to zephir"
mv ${BASENAME}_dollar_dup.txt $ZEPHIR_VUFIND_DOLL_D
gzip -n -f $ZEPHIR_VUFIND_DOLL_D
$ROOTDIR/ftpslib/ftps_zephir_send ${ZEPHIR_VUFIND_DOLL_D}.gz 

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem sending file ${ZEPHIR_VUFIND_DOLL_D}.gz to zephir: rc is $cmdstatus"
  echo $message
  exit
fi

if [[ $today_dash =~ ^20...01.01$ ]]; then
  echo "ERROR: can't run the special jan 1st OAI process"
 # process full zephir file to create file of ingested items
 $ROOTDIR/run_zephir_full_daily.sh

# XXX This will not work since the docker image doesn't have Ruby. OAI
# processing should be migrated to a new system by the end of 2022, but on the
# off chance it isn't we can run this manually.
#
#  ruby get_bib_additional_recs_for_OAI.rb > additional_recs.json
#  gzip -f additional_recs.json
#  zcat ${BASENAME}.json.gz additional_recs.json.gz | sort | uniq > all_recs_for_OAI.json
#  gzip -f all_recs_for_OAI.json
#  $ROOTDIR/zephir2oai.pl -f $YESTERDAY -i all_recs_for_OAI.json.gz -d $ZEPHIR_VUFIND_DELETE -o ${DATADIR_OAI}/zephir_oai_upd_${TODAY} -s 200000000
else
  echo "`date`: run oai process"
  $ROOTDIR/zephir2oai.pl -f $YESTERDAY -i ${BASENAME}.json.gz -d $ZEPHIR_VUFIND_DELETE -o ${DATADIR_OAI}/zephir_oai_upd_${TODAY} -s 200000000
  find $DATADIR_OAI -type f -mtime +30 -exec rm -f {} ';'
  
  # process full zephir file to create file of ingested items
  $ROOTDIR/run_zephir_full_daily.sh
fi

# This should have already been copied to the archive/catalog
rm ${BASENAME}.json.gz

echo "DONE `date`"
# TODO run cleanup_directory.sh?

# echo "copy rights debug file to mdp_govdocs directory"
# todo: why? what uses debug_current?
# cat ${BASENAME}.rights.debug >> $ROOTDIR/data/zephir/debug_current.txt
exit
