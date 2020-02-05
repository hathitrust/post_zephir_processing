ROOTDIR="$(cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )"

source $ROOTDIR/config/.env

# send barcode feed file in return file to zephir ftps site

echo "home is $HOME"

today=`date +%Y%m%d`
today_std=`date +%Y-%m-%d`
script_name=`basename $0`
echo $script_name

# Where we get them from Aaron
echo BARCODES_DIR is $BARCODES_DIR

DEST_FILE=hathi_volumes_ingested_${today}.txt

RPT_FILE=${REPORTS}/${script_name}_${today}_rpt.txt
echo "${script_name}:  started at `date`" > $RPT_FILE


# check for existence of dest file
if [ -e $LOCAL_BARCODES_DIR/$DEST_FILE ]; then
  MESSAGE="$LOCAL_BARCODES_DIR/$DEST_FILE already exists--exitting"
  echo $MESSAGE
  echo $MESSAGE >> $RPT_FILE
  cat $RPT_FILE | mailx -s"$script_name" $EMAIL 
  exit
fi

# create empty file for today
touch $LOCAL_BARCODES_DIR/$DEST_FILE

files=`ls $BARCODES_DIR/barcodes_${today_std}*`
file_list=( `ls $BARCODES_DIR/barcodes_${today_std}*` )
if [ ${#file_list[@]} == 0 ]; then
  echo "*** No files to process today, sending empty file"
  echo "*** No files to process today, sending empty file" >> $RPT_FILE
  echo ""
fi

echo "*** barcode file list is $files"
echo "*** barcode file list is $files" >> $RPT_FILE
if [ ${#file_list[@]} > 0 ]; then 
  echo "*** ${#file_list[@]} files in file_list: $files"
  echo "*** ${#file_list[@]} files in file_list: $files" >> $RPT_FILE
fi

for file in "${file_list[@]}"
do
  echo "*** checking file $file"
  echo "*** checking file $file" >> $RPT_FILE
  if [ ! -f $file ]; then
    echo "*** $file not a file--skipped"
    echo "*** $file not a file--skipped" >> $RPT_FILE
    continue
  fi
  if [ -z $file ]; then
    echo "*** file $file is empty--skipped"
    echo "*** file $file is empty--skipped" >> $RPT_FILE
    continue
  fi
  cat $file >> $LOCAL_BARCODES_DIR/$DEST_FILE
  echo "*** adding file $file to $DEST_FILE"
  echo "*** adding file $file to $DEST_FILE" >> $RPT_FILE
done

wc -l $LOCAL_BARCODES_DIR/$DEST_FILE
wc -l $LOCAL_BARCODES_DIR/$DEST_FILE >> $RPT_FILE

echo "*** sending file $DEST_FILE to zephir"

$ROOTDIR/ftpslib/ftps_zephir_send $LOCAL_BARCODES_DIR/$DEST_FILE
cmdstatus=$?
if [ $cmdstatus != "0" ]; then
  MESSAGE="Problem sending file $LOCAL_BARCODES_DIR/$DEST_FILE to zephir: rc is $cmdstatus"
  echo $MESSAGE >> $RPT_FILE
  cat $RPT_FILE | mailx -s"$script_name" $EMAIL 
  exit
fi

echo "*** moving file $DEST_FILE to $BARCODE_ARCHIVE"
mv $LOCAL_BARCODES_DIR/$DEST_FILE $BARCODE_ARCHIVE
if [ "$file_list" == "" ]; then
  echo "*** no barcode filesto move"
else
  for file in "${file_list[@]}"; do mv $file $BARCODE_ARCHIVE; done
fi

echo "file(s) $file_list sent to zephir as $DEST_FILE" >> $RPT_FILE
cat $RPT_FILE | mailx -s"$script_name" $EMAIL 
exit
