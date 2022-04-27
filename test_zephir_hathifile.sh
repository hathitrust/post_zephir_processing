ROOTDIR="$(cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )"

source $ROOTDIR/config/.env
if [ -x "$(command -v pigz)" ]; then
  zipcommand=pigz
else
  zipcommand=gzip
fi
if [ -x "$(command -v unpigz)" ]; then
  unzipcommand=unpigz
else
  unzipcommand=gunzip
fi

# Duplicates run_process_zephir_incremental.sh but eliminates downstream effects

echo "starting: `date`"

SCRIPTNAME=`basename $0`
zephir_date=`date --date="yesterday" +%Y-%m-%d`
YESTERDAY=`date --date="yesterday" +%Y%m%d`
TODAY=`date +%Y%m%d`
today_dash=`date +%Y-%m-%d`

export us_fed_pub_exception_file="/htdata/govdocs/feddocs_oclc_filter/oclcs_removed_from_registry_${today_dash}.txt"
echo "fed pub exception file set in environment: $us_fed_pub_exception_file"

DATADIR=$ROOTDIR/data/zephir
ARCHIVE=/htapps/archive
#set ZEPHIR_VUFIND_EXPORT=vufind_incremental_${zephir_date}.json.gz 
ZEPHIR_VUFIND_EXPORT=ht_bib_export_incr_${zephir_date}.json.gz 
ZEPHIR_VUFIND_DELETE=vufind_removed_cids_${zephir_date}.txt.gz
ZEPHIR_GROOVE_INCREMENTAL=groove_incremental_${zephir_date}.tsv.gz
ZEPHIR_DAILY_TOUCHED=daily_touched_${zephir_date}.tsv.gz
#set ZEPHIR_GROOVE_FULL=groove_export_${zephir_date}.tsv.gz
ZEPHIR_VUFIND_DOLL_D=vufind_incremental_${zephir_date}_dollar_dup.txt
BASENAME=zephir_upd_${YESTERDAY}
REPORT_FILE=${BASENAME}_report.txt
echo "basename is $BASENAME"

RIGHTS_DBM=$ROOTDIR/tmp/rights_dbm

echo "`date`: zephir incremental extract started" > $REPORT_FILE
echo "`date`: zephir incremental extract started" 

echo "`date`: retrieve $ZEPHIR_VUFIND_EXPORT"
echo "`date`: retrieve $ZEPHIR_VUFIND_EXPORT" >> $REPORT_FILE

ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_VUFIND_EXPORT

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem getting file ${ZEPHIR_VUFIND_EXPORT} from zephir: rc is $cmdstatus"
  echo "error, message is $message"
fi

if [ ! -e $ZEPHIR_VUFIND_EXPORT ]; then
  echo "***"
  echo "file $ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "***"
  exit
fi

echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE"

ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_DELETE $ZEPHIR_VUFIND_DELETE

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem getting file ${ZEPHIR_VUFIND_DELETE} from zephir: rc is $cmdstatus"
  echo "error, message is $message"
  exit
fi

if [ ! -e $ZEPHIR_VUFIND_DELETE ]; then
  echo "***"
  echo "file $ZEPHIR_VUFIND_DELETE not found, exitting"
  echo "***"
  exit
fi


echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL"

ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_INCREMENTAL $ZEPHIR_GROOVE_INCREMENTAL

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  echo "Problem getting file ${ZEPHIR_GROOVE_INCREMENTAL} from zephir: rc is $cmdstatus"
fi

echo "`date`: retrieve $ZEPHIR_DAILY_TOUCHED"

ftpslib/ftps_zephir_get exports/$ZEPHIR_DAILY_TOUCHED $ZEPHIR_DAILY_TOUCHED

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  echo "***"
  echo "Problem getting file ${ZEPHIR_DAILY_TOUCHED} from zephir: rc is $cmdstatus"
  echo "***"
fi

echo "`date`: dump the rights db to a dbm file"
$ROOTDIR/bld_rights_db.pl -x $RIGHTS_DBM

echo "`date`: processing file $ZEPHIR_VUFIND_EXPORT"
$ROOTDIR/zephir_hathifile.pl -i $ZEPHIR_VUFIND_EXPORT -o ${BASENAME} -r ${BASENAME}.rights -d -f $RIGHTS_DBM -u $YESTERDAY > ${BASENAME}_stderr 
tail -50 ${BASENAME}_rpt.txt

zcat $ZEPHIR_VUFIND_DELETE > ${BASENAME}_zephir_delete.txt
sort -u ${BASENAME}_zephir_delete.txt ${BASENAME}_delete.txt -o ${BASENAME}_all_delete.txt

echo "`date`: rights file ${BASENAME}.rights"

echo "`date`: json file: ${BASENAME}.json"

echo "`date`: combined delete file ${BASENAME}_delete.txt"

echo "`date`: hathi file ${BASENAME}_hathi.txt"

echo "`date`: dollar dup files: ${BASENAME}_dollar_dup.txt"

echo "DONE `date`"
