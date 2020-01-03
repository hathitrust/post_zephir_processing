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

echo "starting: `date`"

SCRIPTNAME=`basename $0`
zephir_date=`date --date="yesterday" +%Y-%m-%d`
YESTERDAY=`date --date="yesterday" +%Y%m%d`
TODAY=`date +%Y%m%d`
today_dash=`date +%Y-%m-%d`

export us_fed_pub_exception_file="/htdata/govdocs/feddocs_oclc_filter/oclcs_removed_from_registry_${today_dash}.txt"
echo "fed pub exception file set in environment: $us_fed_pub_exception_file"

#moved to the configs
# todo: this still needs to be determined. 
# set HT_WEB_ID='/exlibris/aleph/.ssh/id_rsa_libadm_macc-ht-web-000'
# set HT_WEB_HOST='libadm@macc-ht-web-001.umdl.umich.edu'
# set HT_WEB_DIR='/htapps/www/sites/www.hathitrust.org/files/hathifiles'

#set DATADIR=/aleph-prep/zephir-data
DATADIR=$ROOTDIR/data/zephir
DATADIR_OAI=$ROOTDIR/zephir/oai_data
# todo: make sure we have access
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

RIGHTS_DBM=/tmp/rights_dbm

echo "`date`: zephir incremental extract started" > $REPORT_FILE
echo "`date`: zephir incremental extract started" 

echo "`date`: retrieve $ZEPHIR_VUFIND_EXPORT"
echo "`date`: retrieve $ZEPHIR_VUFIND_EXPORT" >> $REPORT_FILE
# todo: uncomment
ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_VUFIND_EXPORT

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem getting file ${ZEPHIR_VUFIND_EXPORT} from zephir: rc is $cmdstatus"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" jstever@umich.edu
fi

if [ ! -e $ZEPHIR_VUFIND_EXPORT ]; then
  echo "***"
  echo "file $ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "***"
  message="file $ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" jstever@umich.edu
  exit
fi

echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE"
echo "`date`: retrieve $ZEPHIR_VUFIND_DELETE" >> $REPORT_FILE
# todo: uncomment
ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_DELETE $ZEPHIR_VUFIND_DELETE

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem getting file ${ZEPHIR_VUFIND_DELETE} from zephir: rc is $cmdstatus"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" jstever@umich.edu
  exit
fi

if [ ! -e $ZEPHIR_VUFIND_DELETE ]; then
  echo "***"
  echo "file $ZEPHIR_VUFIND_DELETE not found, exitting"
  echo "***"
  message="file $ZEPHIR_VUFIND_DELETE not found, exitting"
  echo "error, message is $message"
  echo $message | mailx -s"error in $SCRIPTNAME" jstever@umich.edu
  exit
fi


echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL"
echo "`date`: retrieve $ZEPHIR_GROOVE_INCREMENTAL" >> $REPORT_FILE
# todo: uncomment
ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_INCREMENTAL $ZEPHIR_GROOVE_INCREMENTAL

cmdstatus=$?
if [ $cmdstatus == "0" ]; then
  echo "`date`: copy $ZEPHIR_GROOVE_INCREMENTAL to mdp/return/zephir"
  echo "`date`: copy $ZEPHIR_GROOVE_INCREMENTAL to mdp/return/zephir" >> $REPORT_FILE
  # todo: where should this actually go?
  cp $ZEPHIR_GROOVE_INCREMENTAL $ROOTDIR/data/zephir/
else
  echo "***" >> $REPORT_FILE
  echo "Problem getting file ${ZEPHIR_GROOVE_INCREMENTAL} from zephir: rc is $cmdstatus" >> $REPORT_FILE
  echo "***" >> $REPORT_FILE
fi

echo "`date`: retrieve $ZEPHIR_DAILY_TOUCHED"
echo "`date`: retrieve $ZEPHIR_DAILY_TOUCHED" >> $REPORT_FILE
# todo: uncomment
ftpslib/ftps_zephir_get exports/$ZEPHIR_DAILY_TOUCHED $ZEPHIR_DAILY_TOUCHED

cmdstatus=$?
if [ $cmdstatus == "0" ]; then
  echo "`date`: copy $ZEPHIR_DAILY_TOUCHED to mdp/return/zephir"
  echo "`date`: copy $ZEPHIR_DAILY_TOUCHED to mdp/return/zephir" >> $REPORT_FILE
  #cp $ZEPHIR_DAILY_TOUCHED $data_root/local/mdp/return/zephir/daily_touched.tsv.gz
  cp $ZEPHIR_DAILY_TOUCHED $ROOTDIR/data/zephir/
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
$ROOTDIR/zephir_hathifile.pl -i $ZEPHIR_VUFIND_EXPORT -o ${BASENAME} -r ${BASENAME}.rights -d -f $RIGHTS_DBM -u $YESTERDAY > ${BASENAME}_stderr 
tail -50 ${BASENAME}_rpt.txt >> $REPORT_FILE

zcat $ZEPHIR_VUFIND_DELETE > ${BASENAME}_zephir_delete.txt
sort -u ${BASENAME}_zephir_delete.txt ${BASENAME}_delete.txt -o ${BASENAME}_all_delete.txt
$zipcommand ${BASENAME}_all_delete.txt

echo "`date`: copy rights file ${BASENAME}.rights to data/return/zephir"
echo "`date`: copy rights file ${BASENAME}.rights to data/return/zephir" >> $REPORT_FILE
# todo: where should this actually go?
cp ${BASENAME}.rights $ROOTDIR/data/return/zephir/

echo "`date`: compress json file and send to hathitrust solr server"
echo "`date`: compress json file and send to hathitrust solr server" >> $REPORT_FILE
$zipcommand -n -f ${BASENAME}.json

# todo: uncomment, need the .ssh
# scp -i /exlibris/aleph/.ssh/id_dsa_libadm_beeftea-2 ${BASENAME}.json.gz libadm@beeftea-2:/htsolr/catalog/prep
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem transferring file ${BASENAME}.json.gz to beeftea-2: rc is $cmdstatus"
  echo $message >> $REPORT_FILE
  exit
fi

echo "`date`: copy json file to value storage govdocs folder"
echo "`date`: copy json file to value storage govdocs folder" >> $REPORT_FILE
cp ${BASENAME}.json.gz  /htdata/govdocs/zephir/

# todo: uncomment
# copy to ht archive directory
# cp ${BASENAME}.json.gz  ${ARCHIVE}/catalog/

echo "`date`: send combined delete file to hathitrust solr server as ${BASENAME}_delete.txt.gz"
echo "`date`: send combined delete file to hathitrust solr server as ${BASENAME}_delete.txt.gz" >> $REPORT_FILE

# todo: uncomment, need the .ssh 
# scp -i /exlibris/aleph/.ssh/id_dsa_libadm_beeftea-2 ${BASENAME}_all_delete.txt.gz libadm@beeftea-2:/htsolr/catalog/prep/${BASENAME}_delete.txt.gz
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem transferring file $ZEPHIR_VUFIND_DELETE to beeftea-2: rc is $cmdstatus"
  echo $message >> $REPORT_FILE
  exit
fi

echo "`date`: compress hathi file and send to hathitrust server"
echo "`date`: compress hathi file and send to hathitrust server" >> $REPORT_FILE
HATHIFILE=hathi_upd_${YESTERDAY}.txt
mv ${BASENAME}_hathi.txt $HATHIFILE
$zipcommand -f $HATHIFILE

# todo: we need the web id and host information, uncomment
# scp -i ${HT_WEB_ID} ${HATHIFILE}.gz ${HT_WEB_HOST}:${HT_WEB_DIR}/
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem transferring hathifile to $HT_WEB_HOST: rc is $cmdstatus"
  echo $message >> $REPORT_FILE
  exit
fi

echo "`date`: generate json hathifile list" >> $REPORT_FILE
# todo: again, need the id and host information, uncomment
# ssh -i ${HT_WEB_ID} ${HT_WEB_HOST} /htapps/www/sites/www.hathitrust.org/extra_perl/json_filelist.pl >> $REPORT_FILE

# copy hathifile to ht archive directory
# todo: uncomment
# cp ${HATHIFILE}.gz ${ARCHIVE}/hathifiles/

echo "`date`: compress dollar dup files and send to zephir"
echo "`date`: compress dollar dup files and send to zephir" >> $REPORT_FILE
mv ${BASENAME}_dollar_dup.txt $ZEPHIR_VUFIND_DOLL_D
$zipcommand -n -f $ZEPHIR_VUFIND_DOLL_D
# todo: uncomment
# ftpslib/ftps_zephir_send ${ZEPHIR_VUFIND_DOLL_D}.gz 

cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem sending file ${ZEPHIR_VUFIND_DOLL_D}.gz to zephir: rc is $cmdstatus"
  echo $message >> $REPORT_FILE
  exit
fi

#echo "`date`: copy aleph json file to add_zephir_holdings data directory"
#echo "`date`: copy aleph json file to add_zephir_holdings data directory" >> $REPORT_FILE
#cp ${BASENAME}_aleph.json $alephe_dev/miu01/local/add_zephir_holdings/data/

echo "`date`: run oai process" >> $REPORT_FILE
$ROOTDIR/zephir2oai.pl -f $YESTERDAY -i ${BASENAME}.json.gz -d $ZEPHIR_VUFIND_DELETE -o ${DATADIR_OAI}/zephir_oai_upd_${TODAY} -s 200000000
find $DATADIR_OAI -type f -mtime +30 -exec rm -f {} ';'

echo "DONE `date`"
echo "DONE `date`" >> $REPORT_FILE
cat $REPORT_FILE | mailx -s"$SCRIPTNAME report: $TODAY" jstever@umich.edu

echo "copy rights debug file to mdp_govdocs directory" >> $REPORT_FILE
# todo: why? what uses debug_current?
# cat ${BASENAME}.rights.debug >> $ROOTDIR/data/zephir/debug_current.txt

# process full zephir file to create file of ingested items and HTRC datasets metadata
$ROOTDIR/run_zephir_full_daily.sh

#exit
#set DAY=`day`
#if ($DAY == "01") then
#  echo "starting run_process_zephir_full" >> $REPORT_FILE
#  $PROGDIR/run_process_zephir_full 
#else
#  echo "not first day of month, not starting run_process_zephir_full" >> $REPORT_FILE
#endif

exit

# this has been transcribe where it is needed
#error_exit:
#echo "error, message is $message"
#echo $message | mailx -s"error in $SCRIPTNAME" jstever@umich.edu
