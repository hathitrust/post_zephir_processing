ROOTDIR="$(cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )"

source $ROOTDIR/config/.env

echo "starting: `date`"

TODAY=`date +%Y%m%d`
FILE=repository_ids_${TODAY}.txt

rm -f $REPOSITORY_IDS/repository_ids.txt
rm -f $REPOSITORY_IDS/repository_ids.txt.gz


mysql $DB_NAME --skip-column-names -h mysql-sdr -u $DB_USER -p$DB_PASSWORD <<EOF > repository_ids.txt

select 
  concat(a1.namespace, '.', a1.id)
from 
  feed_audit a1 left join feed_audit a2
  on a1.namespace = a2.namespace and a2.id = concat('\\$',a1.id) 
where
  a2.id is null

EOF

wc -l repository_ids.txt

if [ -x "$(command -v pigz)" ]; then
  pigz repository_ids.txt
else
  gzip repository_ids.txt
fi

# todo: uncomment
# ftps_zephir_send repository_ids.txt.gz $FILE.gz 

mv repository_ids.txt.gz $REPOSITORY_IDS/repository_ids.txt.gz
