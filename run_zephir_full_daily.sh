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
us_fed_pub_exception_file=/htdata/govdocs/feddocs_oclc_filter/oclcs_removed_from_registry_${today_dash}.txt
echo "fed pub exception file set in environment: $us_fed_pub_exception_file"

# File from zephir contains 6060217 record (2013-10-21)
SPLITCOUNT=1000000

ZEPHIR_VUFIND_EXPORT=ht_bib_export_full_${zephir_date}.json.gz
ZEPHIR_GROOVE_EXPORT=groove_export_${zephir_date}.tsv.gz
REPORT_FILE=$ZEPHIR_DATA/zephir_full_daily_report.txt

echo "basename is zephir_full_daily"

RIGHTS_DBM=$ROOTDIR/tmp/rights_dbm

echo "`date`: zephir full extract started" > $REPORT_FILE
echo "`date`: zephir full extract started" 

echo "`date`: retrieve zephir files: groove_export_${zephir_date}.tsv.gz" >> $REPORT_FILE
echo "`date`: retrieve zephir files: $ZEPHIR_GROOVE_EXPORT"

ftpslib/ftps_zephir_get exports/$ZEPHIR_GROOVE_EXPORT $ZEPHIR_GROOVE_EXPORT
if [ ! -e $ZEPHIR_GROOVE_EXPORT ]; then
  echo "***"
  echo "file $ZEPHIR_GROOVE_EXPORT not found, exiting"
  echo "***"
  exit
fi

mv $ZEPHIR_GROOVE_EXPORT /htapps/babel/feed/var/bibrecords/groove_full.tsv.gz

echo "*** retrieve full zephir vufind extract" >> $REPORT_FILE
echo "*** retrieve full zephir vufind extract"

ftpslib/ftps_zephir_get exports/$ZEPHIR_VUFIND_EXPORT $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT
if [ ! -e $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT ]; then
  echo "***"
  echo "file $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT not found, exitting"
  echo "***"
  exit
fi

echo "*** dump the rights db to a dbm file"
$ROOTDIR/bld_rights_db.pl -x $RIGHTS_DBM

# split the json file 
echo "*** split the json file"
rm -f zephir_full_daily_??
echo input file is $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT
ls -l $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT

$unzipcommand -c $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT | split -l $SPLITCOUNT - zephir_full_daily_

file_list=`ls zephir_full_daily_??`
echo "file_list: $file_list"

for file in $file_list; do
  echo "`date`: processing file $file"
  `$ROOTDIR/postZephir.pm -z 1 -i $file -o ${file}_out -r ${file}.rights -d -f $RIGHTS_DBM &> ${file}_stderr &`
done

# wait loop: check last line of each rpt file
# exit from loop when all are done (last line eq "DONE")
echo "`date`: wait for post_zephir_cleanup processes to end" >> $REPORT_FILE
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

echo "`date`: all files processed, concatenate htrc files" 
echo "`date`: all files processed, concatenate htrc files" >> $REPORT_FILE
types=(ic pd_google pd_open_access restricted)
for type in "${types[@]}"
do
  echo "combining $type files"
  cat zephir_full_daily_??_out_meta_${type}.jsonl | ${zipcommand} -c > meta_${type}_${TODAY}.jsonl.gz
done
for type in "${types[@]}" 
do
  echo "move combined $type file to transfer directory"
  mv meta_${type}_${TODAY}.jsonl.gz ${META_DIR}/
done

echo "`date`: all files processed, concatenate and compress files to zephir_ingested_items.txt.gz" 
echo "`date`: all files processed, concatenate and compress files to zephir_ingested_items.txt.gz" >> $REPORT_FILE
cat zephir_full_daily_??_out_zia.txt | ${zipcommand} -c > zephir_ingested_items.txt.gz
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem concatenating files: rc is $cmdstatus"
  echo "error, message is $message"
  echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
fi
echo "`zcat zephir_ingested_items.txt.gz | wc -l` lines in zephir ingested items file" >> $REPORT_FILE
cp zephir_ingested_items.txt.gz /htapps/babel/feed/var/bibrecords
mv zephir_ingested_items.txt.gz $DATA_ROOT 

DAY=`date +%d`
if [ $DAY == "01" ]; then
  echo "First day of month--prepare and deliver monthly output"
  echo "First day of month--prepare and deliver monthly output" >> $REPORT_FILE

  echo "`date`: all files processed, concatenate and compress vufind json files to zephir_full_${YESTERDAY}_vufind.json.gz" 
  echo "`date`: all files processed, concatenate and compress vufind json files to zephir_full_${YESTERDAY}_vufind.json.gz" >> $REPORT_FILE
  cat zephir_full_daily_??_out.json | ${zipcommand} -c > zephir_full_${YESTERDAY}_vufind.json.gz
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="Problem concatenating vufind json files: rc is $cmdstatus"
    echo "error, message is $message"
    echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
  fi
  cp zephir_full_${YESTERDAY}_vufind.json.gz $ZEPHIR_DATA/full/zephir_full_${YESTERDAY}_vufind.json.gz
  echo "`date`: sending full file to hathi trust catalog solr server" >> $REPORT_FILE
  cp ${ZEPHIR_DATA}/full/zephir_full_${YESTERDAY}_vufind.json.gz /htsolr/catalog/prep 
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="Problem transferring file to beeftea-2: rc is $cmdstatus"
    #goto error_exit
    echo "error, message is $message"
    echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
  fi
  echo "`date`: copy full file to value storage govdocs folder" >> $REPORT_FILE
  cp zephir_full_${YESTERDAY}_vufind.json.gz  /htdata/govdocs/zephir/
  cp zephir_full_${YESTERDAY}_vufind.json.gz  $ZEPHIR_ARCHIVE/
  cp zephir_full_${YESTERDAY}_vufind.json.gz /htapps/archive/catalog/

  echo "`date`: all files processed, concatenate rights files to zephir_full_${YESTERDAY}.rights"
  echo "`date`: all files processed, concatenate rights files to zephir_full_${YESTERDAY}.rights" >> $REPORT_FILE
  cat zephir_full_daily_??.rights > zephir_full_${YESTERDAY}.rights 
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="Problem concatenating rights files: rc is $cmdstatus"
    echo "error, message is $message"
    echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
  fi
  cp zephir_full_${YESTERDAY}.rights /htapps/babel/feed/var/rights/
  cp zephir_full_${YESTERDAY}.rights $ZEPHIR_DATA/full/
  cp zephir_full_${YESTERDAY}.rights $DATA_ROOT/zephir/
  
  echo "`date`: all files processed, concatenate rights debug files to zephir_full_${YESTERDAY}.rights.debug"
  echo "`date`: all files processed, concatenate rights debug files to zephir_full_${YESTERDAY}.rights.debug" >> $REPORT_FILE
  cat zephir_full_daily_??.rights.debug > zephir_full_${YESTERDAY}.rights.debug 
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="Problem concatenating rights debug files: rc is $cmdstatus"
    echo "error, message is $message"
    echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
  fi
  
  echo "`date`: all files processed, concatenate rights chg files to zephir_full_${YESTERDAY}.rights.tsv" 
  echo "`date`: all files processed, concatenate rights chg files to zephir_full_${YESTERDAY}.rights.tsv" >> $REPORT_FILE
  sort -u zephir_full_daily_??.rights_rpt.tsv -o zephir_full_${YESTERDAY}.rights.tsv 
  cmdstatus=$?
  if [ $cmdstatus != "0" ]; then
    message="Problem sorting rights report files: rc is $cmdstatus"
    #goto error_exit
    echo "error, message is $message"
    echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
  fi
  cp zephir_full_${YESTERDAY}.rights.tsv $ZEPHIR_DATA/full/
fi

echo "`date`: all files processed, concatenate report files to zephir_full_daily_rpt.txt" 
echo "`date`: all files processed, concatenate report files to zephir_full_daily_rpt.txt" >> $REPORT_FILE
cat zephir_full_daily_??_out_rpt.txt > zephir_full_daily_rpt.txt 
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  message="Problem concatenating report files: rc is $cmdstatus"
  echo "error, message is $message"
  echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
fi
cp zephir_full_daily_rpt.txt $ZEPHIR_DATA/full/ 

echo "`date`: cleanup--counts"
echo "`date`: cleanup--counts" >> $REPORT_FILE
zephir_count=`$unzipcommand -c $ZEPHIR_DATA/$ZEPHIR_VUFIND_EXPORT | wc -l`
hathi_catalog_count=`$unzipcommand -c zephir_full_${YESTERDAY}_vufind.json.gz | wc -l`
hathifiles_count=`$unzipcommand -c hathi_full_${TODAY}.txt.gz | wc -l`
echo "`date`: $zephir_count records in full zephir export json file" >> $REPORT_FILE
echo "`date`: $hathi_catalog_count records in full hathi catalog json file" >> $REPORT_FILE
echo "`date`: $hathifiles_count records in full hathifiles extract" >> $REPORT_FILE
echo >> $REPORT_FILE

echo "`date`: cleanup--remove intermediate files" 
echo "`date`: cleanup--remove intermediate files" >> $REPORT_FILE
cat zephir_full_daily_*stderr > stderr.tmp.txt
rm zephir_full_daily_??
rm zephir_full_daily_??_*
rm zephir_full_daily_??.*

echo "`date`: DONE"
echo "`date`: DONE" >> $REPORT_FILE
cat $REPORT_FILE | mailx -s"$SCRIPTNAME report: $TODAY" $EMAIL
exit

# this has been transcribed where it is needed
#error_exit:
#echo "error, message is $message"
#echo "$message" | mailx -s"error in $SCRIPTNAME" $EMAIL
