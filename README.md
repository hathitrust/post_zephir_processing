Post-Zephir Metadata Processing
===============================

A mostly haphazard collection of scripts (Bash, Perl) that take Zephir records, do some clean up, generate the Hathifiles, and calculate Bib Rights, among other processes.

Parts of these should likely be extracted into their own repositories, or obviated by a re-architecture. 

#todo: needs to be replaced in multiple files


run_hathi_volumes_ingested_zephir.sh (daily)
====================================
* Send file of ingested volumes to Zephir
* Concatenates all files of the proper name to one file to send
* File(s) provided by ingest (feed)
* Gets moved to root_dir/data/barcode_archive 

Why?
---
This takes the new barcodes from ingest (feed) and sends them to Zephir. Zephir needs to know which records to include in the export so that the item info (974) will be included in the next day's extract, either for the first time if it's newly ingested, or with an updated 974$d so that full-text search will reindex it. This seems like a complex way to perform a table join.

Data In
--------
* barcodes_YYY-MM-DD_ (previously: /exlibris/aleph/uprod/miu50/local/mdp/return/) New preferred directory: /htdata/return/ ?

Data Out
--------
* hathi_volumes_ingested_YYYYMMDD.txt sent to ftps.cdlib.org (untested)
* run_hathi_volumes_ingested_zephir.sh_YYYYMMDD_rpt.txt sent to $EMAIL (jstever@umich.edu)
* moving barcode input files into an archive directory ($root/data/barcode_archive)

Perl script dependencies
------------------------
* None

Bash script dependencies
------------------------
* ftps_zephir_send ( shell script, dependent upon .netrc credentials)


get_all_repository_ids.sh (weekly)
=========================
* Get file of all HTIDs in the repository from the feed_audit table(?) and send to zephir
* Performs a single query on the mysql database. 
* Runs weekly. 

Why?
----
Auditing. Zephir needs to make sure there wasn't a missed incremental or something that didn't make it into an incremental on HT's end.

Data In
-------
* feed_audit table in ht_repository database 

Data Out
--------
* repository_ids.txt.gz get sent to Zephir (or they would, but I can't test that) 

Perl script dependencies
------------------------
* None

Bash script dependencies
------------------------
* ftps_zephir_send ( shell script, dependent upon .netrc credentials)


run_process_zephir_incremental.sh (daily)
=========================================
* Process daily file of new/updated/deleted metadata provided by Zephir
* Send deleted bib record IDs (provided by Zephir) to Bill
* "Clean up" zephir records
* (re)determine bibliographic rights
  + Write new/updated bib rights to file for Aaron's process to pick up and update the rights db (Why: possibly because of limited permissions on the rights database)
* File of processed new/updated records is copied to an HT server for Bill to index in the catalog
* Generate daily hathifile update file
  + Send to HT file server used by the HT web server
  + SSH in and run some additional perl script to update stuff.
* Generate OAI update file and make available to the OAI update process (Roger, zephir2oai.pl)
  + Output written to nfs directory on server where OAI update process occurs 
* Delete old OAI files.
* Retrieve files with changed & new records daily_touched_YYYY-MM-DD.tsv.gz and groove_incremental_YYYY_MM-DD.tsv.gz from Zephir for pickup by ingest to be loaded to the `feed_zephir_items` table, which supports determining what items are newly available for ingest, what digitization source we expect to see for those items, and what their collection code (which maps to content provider and responsible source) is
* Retrieves full bib metadata file from zephir and generates the HTRC datasets metadata with run_zephir_full_daily.sh. (Why?)

Why?
----
The new/updated/deleted metadata provided by Zephir needs to make it to the catalog, and eventually into the rights database. 

Data In
-------
* `ht_bib_export_incr_YYYY-MM-DD.json.gz` (incremental updates from Zephir, `ftps_zephir_get`)
* `vufind_removed_cids_YYYY-MM-DD.txt.gz` (CIDs that have gone away, `ftps_zephir_get`)
* `groove_incremental_YYYY-MM-DD.tsv.gz`  (from Zephir - new items added to Zephir?)
* `/tmp/rights_dbm`  (taken from `ht_rights.rights_current` table in the rights database)
* `us_cities.db` (dependency for `bib_rights.pm`)
* `us_fed_pub_exception_file` (dependency for `bib_rights.pm`, `/htdata/govdocs/feddocs_oclc_filter/`) 
* `namespacemap.yml` (namespaces, how is this maintained?)

Data Out
--------
* `debug_current.txt` (what and why for this?)
* `zephir_upd_YYYYMMDD.rights` - picked up hourly by https://github.com/hathitrust/feed_jobs/blob/master/feed.hourly/populate_rights_data.pl and loaded into the `rights_current` table. Could just place directly in /htprep/babel/feed/var/rights and remove the scp logic from populate_rights_data.pl
* `zephir_upd_YYYYMMDD_delete.txt.gz` (scp to solr/catalog/prep on the server, .ssh id required)
* `hathi_upd_YYYYMMDD.txt` (hathifile, scp to the HT web host)
* `zephir_upd_YYYYMMDD_dollar_dup.txt `(generated by zephir_hathifile.pl, gets sent to Zephir, ftps_zephir_send, Zephir uningests these duplicate records)
* Updated bibliographic records - used by https://github.com/hathitrust/feed_jobs/blob/master/feed.daily/02_get_bibrecords.pl to update the feed_zephir_items table on a daily basis. Could place directly in /htapps/babel/feed/var/bibrecords and remove the scp logic in `02_get_bibrecords.pl`, or just have `02_get_bibrecords.pl` call `ftps_zephir_get` directly: `daily_touched_YYYY-MM-DD.txt.gz` and `groove_incremental_YYYY-MM-DD.tsv.gz` (Retrieved with `ftps_zephir_get`.)
* `zephir_oai_upd_YYYYMMDD_oaimarc_seqnum.xml` (currently going to `/aleph-22_1/aleph/uprod/miu50/local/mdp_batch/zephir/oai_data`. Where should it go?)
* `meta_(ic|pd_google|pd_open_access|restricted)_20200107.jsonl.gz` (currently going to `/aleph-22_1/aleph/uprod/miu50/local/mdp_batch/return/transfer`) Used by datasets. Currently copied from gimlet to `/htprep/datasets/ht_bib` at ICTC by `/l/local/bin/getmeta.sh` on quik-1 
* `zephir_ingested_items.txt.gz` - scped from `gimlet` to `/htapps/babel/feed/var/bibrecords` to temporary location `/ram/zephir_items` on macc-ht-ingest-001 by https://github.com/hathitrust/feed_jobs/blob/master/feed.monthly/zephir_diff.pl. Used to refresh the full `feed_zephir_items` table on a monthly basis.
* `zephir_full_daily_rpt.tx`t Does anyone need this?

Perl script dependencies
------------------------
* `bld_rights_db.pl` (builds `/tmp/rights_dbm`)
* `bib_rights.pm`
* `zephir_hathifile.pl`

Bash script dependencies
------------------------
* `ftps_zephir_get`
* `ftps_zephir_send`
* `run_process_zephir_full.sh`

run_zephir_full_daily.sh (daily, and monthly)
=============================================
* Pulls a full bib metadata file from zephir and generates the HTRC datasets metadata (parameter to zephir_hathifile.pl)
  + Files written to a directory and rsynced to HTRC server (A&E process)
* On the first of the month, processes the full zephir file:
  + Splits input file and runs multiple invocations of zephir_hathifiles.pl in parallel
  + Generate new/updated bib rights
  + Output a full hathifile, write to HT web fileserver
  + Remove oldest full hathifile and previous month's daily hathifiles

Why?
----
When run daily, mostly for HTRC purposes? 
When run on the 1st of the month, it takes care of the full hathifile. That goes on the website.

Data In
-------
* US Fed Doc exception list `/htdata/govdocs/feddocs_oclc_filter/oclcs_removed_from_registry_YYYY-MM-DD.txt`
* `/tmp/rights_dbm`
* `groove_export_YYYY-MM-DD.tsv.gz` (ftps from cdlib)
* `ht_bib_export_full_YYYY-MM-DD.json.gz`

Data Out
--------
* `groove_export_YYYY-MM-DD.tsv.gz` gets moved to return/groove_full.tsv.gz (why?)
* `hathi_full_YYYYMMDD.txt`
* `meta_(ic, pd_google, pd_open_Access, restricted)_YYYYMMDD.jsonl.gz`
* `zephir_full_${YESTERDAY}_vufind.json.gz`
* `zephir_full_${YESTERDAY}.rights`
* `zephir_full_${YESTERDAY}.rights.tsv`
* `zephir_full_${YESTERDAY}.rights.debug`
* `zephir_full_daily_rpt.txt`

Perl script dependencies
------------------------
* `bld_rights_db.pl`
* `bib_rights.pm`
* `zephir_hathifile.pl`

Bash script dependencies
------------------------
* `ftps_zephir_get`
* `ftps_zephir_send`


Setup
=====
Fill out the config/.env and config/.netrc files.

```bash
wget https://cpan.metacpan.org/authors/id/H/HA/HAARG/local-lib-2.000024.tar.gz
tar -xzf local-lib-2.000024.tar.gz
cd local-lib-2.000024
perl Makefile.PL --bootstrap=/l1/govdocs/zcode/local
make test && make install
curl -L http://cpanmin.us | perl - App::cpanminus
cpanm --install-deps .
```
