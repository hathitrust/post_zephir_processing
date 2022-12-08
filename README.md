Post-Zephir Metadata Processing
===============================

A mostly haphazard collection of scripts (Bash, Perl) that take Zephir records, do some clean up and calculate Bib Rights, among other processes.

Parts of these should likely be extracted into their own repositories, or obviated by a re-architecture. 

run_process_zephir_incremental.sh (daily)
=========================================
* Process daily file of new/updated/deleted metadata provided by Zephir
* Send deleted bib record IDs (provided by Zephir) to Bill
* "Clean up" zephir records
* (re)determine bibliographic rights
  + Write new/updated bib rights to file for Aaron's process to pick up and update the rights db (Why: possibly because of limited permissions on the rights database)
* File of processed new/updated records is copied to an HT server for Bill to index in the catalog
* Generate OAI update file and make available to the OAI update process (Roger, zephir2oai.pl)
  + Output written to nfs directory on server where OAI update process occurs 
* Delete old OAI files.
* Retrieve files with changed & new records daily_touched_YYYY-MM-DD.tsv.gz and groove_incremental_YYYY_MM-DD.tsv.gz from Zephir for pickup by ingest to be loaded to the `feed_zephir_items` table, which supports determining what items are newly available for ingest, what digitization source we expect to see for those items, and what their collection code (which maps to content provider and responsible source) is
* Retrieves full bib metadata file from zephir and runs run_zephir_full_daily.sh. (Why?)

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

Data Out
--------
* `debug_current.txt` (what and why for this?)
* `zephir_upd_YYYYMMDD.rights` - picked up hourly by https://github.com/hathitrust/feed_internal/blob/master/feed.hourly/populate_rights_data.pl and loaded into the `rights_current` table. Will be placed directly in /htapps/babel/feed/var/rights and will remove the scp logic from populate_rights_data.pl
* `zephir_upd_YYYYMMDD_delete.txt.gz`  will be moved to /htsolr/catalog/prep. Used by the catalog to process deletes.
* `zephir_upd_YYYYMMDD_dollar_dup.txt `(generated by post_zephir_cleanup.pl, gets sent to Zephir, ftps_zephir_send, Zephir uningests these duplicate records)
* `zephir_upd_YYYYMMDD.json.gz` will be sent to /htsolr/catalog/prep for [catalog indexing](https://github.com/hathitrust/hathitrust_catalog_indexer)
* Updated bibliographic records - used by https://github.com/hathitrust/feed_internal/blob/master/feed.daily/02_get_bibrecords.pl to update the feed_zephir_items table on a daily basis. Could place directly in /htapps/babel/feed/var/bibrecords and remove the scp logic in `02_get_bibrecords.pl`, or just have `02_get_bibrecords.pl` call `ftps_zephir_get` directly: `daily_touched_YYYY-MM-DD.txt.gz` and `groove_incremental_YYYY-MM-DD.tsv.gz` (Retrieved with `ftps_zephir_get`.)  `daily_touched*.txt.gz` and `groove_incremental*.tsv.gz` will be placed in /htapps/babel/feed/var/bibrecords
* `zephir_oai_upd_YYYYMMDD_oaimarc_seqnum.xml` currently going to /htdev/htdata/oai. Soon to be deprecated (2022-06-20).
* `zephir_full_daily_rpt.txt` Does anyone need this?

Perl script dependencies
------------------------
* `bld_rights_db.pl` (builds `/tmp/rights_dbm`)
* `bib_rights.pm`
* `postZephir.pm`

Bash script dependencies
------------------------
* `ftps_zephir_get`
* `ftps_zephir_send`
* `run_process_zephir_full.sh`

run_zephir_full_daily.sh (daily, and monthly)
=============================================
* Pulls a full bib metadata file from zephir
* Moves groove_full.tsv.gz to /htapps/babel/feed/var/bibrecords
* Assembles zephir_ingested_items.txt.gz and moves to /htapps/babel/feed/var/bibrecords
* On the first of the month, processes the full zephir file:
  + Splits input file and runs multiple invocations of postZephir.pm in parallel
  + Generate new/updated bib rights

Why?
----
Previously generated the HTRC datasets. All that remains is the zephir_ingested_items and bib rights.

Data In
-------
* US Fed Doc exception list `/htdata/govdocs/feddocs_oclc_filter/oclcs_removed_from_registry.txt`
* `/tmp/rights_dbm`
* `groove_export_YYYY-MM-DD.tsv.gz` (ftps from cdlib)
* `ht_bib_export_full_YYYY-MM-DD.json.gz`

Data Out
--------
* `groove_export_YYYY-MM-DD.tsv.gz` will be moved to /htapps/babel/feed/var/bibrecords/groove_full.tsv.gz  
* `zephir_full_${YESTERDAY}_vufind.json.gz` catalog archive. Indexed into catalog via the same process as for `run_process_zephir_incremental.sh`
* `zephir_full_${YESTERDAY}.rights` moved to /htapps/babel/feed/var/rights/
* `zephir_full_${YESTERDAY}.rights.debug`, doesn't appear to be used
* `zephir_full_daily_rpt.txt`moved to ../data/full/
* `zephir_full_${YESTERDAY}.rights_rpt.tsv moved to ./data/full/
* `zephir_ingested_items.txt.gz` - copied to `/htapps/babel/feed/var/bibrecords`. Used by https://github.com/hathitrust/feed_internal/blob/master/feed.monthly/zephir_diff.pl to refresh the full `feed_zephir_items` table on a monthly basis.

Perl script dependencies
------------------------
* `bld_rights_db.pl`
* `bib_rights.pm`
* `postZephir.pm`

Bash script dependencies
------------------------
* `ftps_zephir_get`
* `ftps_zephir_send`


Running Tests
====
Tests with limited coverage can be run with Docker.

```bash
docker-compose build
docker-compose up -d
docker-compose run --rm pz perl t/test_postZephir.t
```

For test coverage, replace the previous `docker-compose run` with
```bash
docker-compose run --rm pz bash -c "perl -MDevel::Cover=-silent,1 t/test_postZephir.pl && cover -nosummary /usr/src/app/cover_db"
```
