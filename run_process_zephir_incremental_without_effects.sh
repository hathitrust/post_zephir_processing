# Ideally the same as run_process_zephir_incremental.sh but doesn't pass on results downstream

ROOTDIR="$(cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )"

source $ROOTDIR/config/.env

echo "starting: `date`"

SCRIPTNAME=`basename $0`
zephir_date=`date --date="yesterday" +%Y-%m-%d`
YESTERDAY=`date --date="yesterday" +%Y%m%d`
TODAY=`date +%Y%m%d`
today_dash=`date +%Y-%m-%d`

export us_fed_pub_exception_file="/htdata/govdocs/feddocs_oclc_filter/oclcs_removed_from_registry_${today_dash}.txt"
echo "fed pub exception file set in environment: $us_fed_pub_exception_file"

#moved to the configs
# HT_WEB_DIR='/htapps/www/sites/www.hathitrust.org/files/hathifiles'

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

# ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_VUFIND_EXPORT
ZEPHIR_VUFIND_EXPORT=$1
echo "Using file ${ZEPHIR_VUFIND_EXPORT} from zephir supplied by user"

if [ ! -e $ZEPHIR_VUFIND_EXPORT ]; then
  echo "***"
  echo "file $ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "***"
  message="file $ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "error, message is $message"
  exit
fi

echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE"
echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE" >> $REPORT_FILE

# ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_DELETE $ZEPHIR_VUFIND_DELETE
ZEPHIR_VUFIND_DELETE=$2
echo "Using file ${ZEPHIR_VUFIND_DELETE} from zephir supplied by user"

if [ ! -e $ZEPHIR_VUFIND_DELETE ]; then
  echo "***"
  echo "file $ZEPHIR_VUFIND_DELETE not found, exitting"
  echo "***"
  message="file $ZEPHIR_VUFIND_DELETE not found, exitting"
  echo "error, message is $message"
  exit
fi


echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL"
echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL" >> $REPORT_FILE

ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_INCREMENTAL $ZEPHIR_GROOVE_INCREMENTAL

cmdstatus=$?
if [ $cmdstatus == "0" ]; then
  echo "`date`: (dont) copy $ZEPHIR_GROOVE_INCREMENTAL to rootdir/data/zephir"
  echo "`date`: (dont) copy $ZEPHIR_GROOVE_INCREMENTAL to rootdir/data/zephir" >> $REPORT_FILE
  # should go here:
  # mv $ZEPHIR_GROOVE_INCREMENTAL /htapps/babel/feed/var/bibrecords/
  #mv $ZEPHIR_GROOVE_INCREMENTAL $ROOTDIR/data/zephir/
else
  echo "***" >> $REPORT_FILE
  echo "Problem getting file ${ZEPHIR_GROOVE_INCREMENTAL} from zephir: rc is $cmdstatus" >> $REPORT_FILE
  echo "***" >> $REPORT_FILE
fi

echo "`date`: retrieve $ZEPHIR_DAILY_TOUCHED"
echo "`date`: retrieve $ZEPHIR_DAILY_TOUCHED" >> $REPORT_FILE

ftpslib/ftps_zephir_get exports/$ZEPHIR_DAILY_TOUCHED $ZEPHIR_DAILY_TOUCHED

cmdstatus=$?
if [ $cmdstatus == "0" ]; then
  echo "`date`: (dont) copy $ZEPHIR_DAILY_TOUCHED to /htapps/babel/feed/var/bibrecords"
  echo "`date`: (dont) copy $ZEPHIR_DAILY_TOUCHED to /htapps/babel/feed/var/bibrecords" >> $REPORT_FILE
  #cp $ZEPHIR_DAILY_TOUCHED $data_root/local/mdp/return/zephir/daily_touched.tsv.gz
  #cp $ZEPHIR_DAILY_TOUCHED /htapps/babel/feed/var/bibrecords
  #mv $ZEPHIR_DAILY_TOUCHED $ROOTDIR/data/zephir/
else 
  echo "***" >> $REPORT_FILE
  echo "Problem getting file ${ZEPHIR_DAILY_TOUCHED} from zephir: rc is $cmdstatus" >> $REPORT_FILE
  echo "***" >> $REPORT_FILE
fi

echo "`date`: dump the rights db to a dbm file"
echo "`date`: dump the rights db to a dbm file" >> $REPORT_FILE
$ROOTDIR/bld_rights_db.pl -x $RIGHTS_DBM

echo "`date`: processing file $ZEPHIR_VUFIND_EXPORT"
echo "`date`: processing file $ZEPHIR_VUFIND_EXPORT" >> $REPORT_FILE
$ROOTDIR/postZephir.pm -i $ZEPHIR_VUFIND_EXPORT -o ${BASENAME} -r ${BASENAME}.rights -d -f $RIGHTS_DBM > ${BASENAME}_stderr 
tail -50 ${BASENAME}_rpt.txt >> $REPORT_FILE

zcat $ZEPHIR_VUFIND_DELETE > ${BASENAME}_zephir_delete.txt
sort -u ${BASENAME}_zephir_delete.txt ${BASENAME}_delete.txt -o ${BASENAME}_all_delete.txt
gzip ${BASENAME}_all_delete.txt

echo "`date`: (dont) copy rights file ${BASENAME}.rights to /htapps/babel/feed/var/rights"
echo "`date`: (dont) copy rights file ${BASENAME}.rights to /htapps/babel/feed/var/rights" >> $REPORT_FILE
#cp ${BASENAME}.rights /htapps/babel/feed/var/rights 
#mv ${BASENAME}.rights $ROOTDIR/data/return/zephir/

echo "`date`: (dont) compress json file and send to hathitrust solr server"
echo "`date`: (dont) compress json file and send to hathitrust solr server" >> $REPORT_FILE
# cp ${BASENAME}.json.gz /htsolr/catalog/prep
message="Did not transfer file ${BASENAME}.json.gz to beeftea-2"
echo $message >> $REPORT_FILE

echo "`date`: (dont) copy json file to value storage govdocs folder" >> $REPORT_FILE
# cp ${BASENAME}.json.gz  /htdata/govdocs/zephir/

echo "`date`: (dont) send combined delete file to hathitrust solr server as ${BASENAME}_delete.txt.gz"
echo "`date`: (dont) send combined delete file to hathitrust solr server as ${BASENAME}_delete.txt.gz" >> $REPORT_FILE

# cp ${BASENAME}_all_delete.txt.gz /htsolr/catalog/prep/${BASENAME}_delete.txt.gz
message="Did not transfer file $ZEPHIR_VUFIND_DELETE to beeftea-2"
echo $message >> $REPORT_FILE

echo "`date`: (dont) compress dollar dup files and send to zephir"
echo "`date`: (dont) compress dollar dup files and send to zephir" >> $REPORT_FILE
#mv ${BASENAME}_dollar_dup.txt $ZEPHIR_VUFIND_DOLL_D
#gzip -n -f $ZEPHIR_VUFIND_DOLL_D

# nope
# ftpslib/ftps_zephir_send ${ZEPHIR_VUFIND_DOLL_D}.gz 
message="Did not send file ${ZEPHIR_VUFIND_DOLL_D}.gz to zephir"
echo $message >> $REPORT_FILE

echo "`date`: (dont) run oai process" >> $REPORT_FILE
#$ROOTDIR/zephir2oai.pl -f $YESTERDAY -i ${BASENAME}.json.gz -d $ZEPHIR_VUFIND_DELETE -o ${DATADIR_OAI}/zephir_oai_upd_${TODAY} -s 200000000
#find $DATADIR_OAI -type f -mtime +30 -exec rm -f {} ';'

# process full zephir file to create file of ingested items and HTRC datasets metadata
# dont do this
# $ROOTDIR/run_zephir_full_daily.sh

echo "DONE `date`"
echo "DONE `date`" >> $REPORT_FILE
exit
