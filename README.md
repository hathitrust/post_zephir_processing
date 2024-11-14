<p align="center">
<h1>Post-Zephir Metadata Processing</h1>

![Run Tests](https://github.com/hathitrust/post_zephir_processing/workflows/Run%20Tests/badge.svg)
[![Coverage Status](https://coveralls.io/repos/github/hathitrust/post_zephir_processing/badge.svg?branch=main)](https://coveralls.io/github/hathitrust/post_zephir_processing?branch=main)
</p>

A mostly haphazard collection of scripts (Bash, Perl) that take Zephir records,
do some clean up and calculate Bib Rights, among other processes.

Parts of these should likely be extracted into their own repositories, or obviated by a re-architecture. 

## Setup
Clone repo using your protocol of choice.
```
docker compose build
```
There is no need for a `bundle install` step as this is taken care of in the `Dockerfile`.

### Run Tests
#### Perl
```
docker compose run --rm test
```

#### Ruby
```
docker compose run --rm test bundle exec standardrb
docker compose run --rm test bundle exec rspec
```

## Standard Locations

Post-Zephir can read and write files in a number of locations, and it can become bewildering.
Many of the locations (all of them directories) show up again and again. Under Argo these
all come from the `ENV` provided to the workflow. Under Docker the locations are not so scattered,
and all orient themselves to `ENV[ROOTDIR]`. The shell scripts rely on `config/defaults` to fill
in many of these variables. The Ruby scripts orient off the `DATA_ROOT` in `Dockerfile`
but fill in the other locations in a more haphazard manner (see the `directory_for` method in
`lib/derivatives.rb` for an example of how this can go off the rails).

TODO: can we use `dotenv` and `.env` in both the shell scripts and the Ruby code, and get rid of
`config/defaults`? Or can we translate `config/defaults` into Ruby and invoke it from the driver?

| `ENV`               | Standard Location                   | Docker/Default Location       |
| --------            | -------                             | -----                         |
| `CATALOG_ARCHIVE`   | `/htapps/archive/catalog`           | `DATA_ROOT/catalog_archive`   |
| `CATALOG_PREP`      | `/htsolr/catalog/prep`              | `DATA_ROOT/catalog_prep`      |
| `DATA_ROOT`         | `/htprep/zephir`                    | `ROOTDIR/data`                |
| `FEDDOCS_HOME`      | `/htprep/govdocs`                   | `DATA_ROOT/govdocs`           |
| `INGEST_BIBRECORDS` | `/htapps/babel/feed/var/bibrecords` | `DATA_ROOT/ingest_bibrecords` |
| `RIGHTS_DIR`        | `/htapps/babel/feed/var/rights`     | `DATA_ROOT/rights`            |
| `ROOTDIR`           | (not used)                          | `/usr/src/app`                |

Additional derivative paths are set by `config/defaults`, typically from the daily or monthly shell script.
As such they are not available to Ruby code. (Note: there may be some fuzziness between these two
sets since we may decide to let Argo handle one or more of these in future. Look to the Argo metadata
workflow config for authoritative values.)

| `ENV`               | Standard Location                   | Docker/Default Location       | Note             |
| --------            | -------                             | -----                         | ----             |
| `REPORTS`           | `DATA_ROOT/reports`                 | `DATA_ROOT/reports`           | *unused*         |
| `RIGHTS_DBM`        | `DATA_ROOT/rights_dbm`              | `DATA_ROOT/rights_dbm`        | *this is a file* |
| `TMPDIR`            | `DATA_ROOT/work`                    | `/tmp`                        |                  |
| `ZEPHIR_DATA`       | `DATA_ROOT/zephir`                  | `DATA_ROOT/zephir`            |                  |



## `run_process_zephir_incremental.sh` (daily)

* Process daily file of new/updated/deleted metadata provided by Zephir
* Send deleted bib record IDs (provided by Zephir) to catalog indexer
* "Clean up" zephir records (what does this mean?)
* (re)determine bibliographic rights
  + Write new/updated bib rights to file for `populate_rights_data.pl` to pick up and update the rights db
* File of processed new/updated records is copied to a location for the catalog indexer to find it
* Retrieves full bib metadata file from zephir and runs `run_zephir_full_monthly.sh`. (It does?? I don't think so.)

Why?
----
The new/updated/deleted metadata provided by Zephir needs to make it to the catalog, and eventually into the rights database. 

Data In
-------
* `ht_bib_export_incr_YYYY-MM-DD.json.gz` (incremental updates from Zephir, `ftps_zephir_get`)
* `vufind_removed_cids_YYYY-MM-DD.txt.gz` (CIDs that have gone away, `ftps_zephir_get`)
* `DATA_ROOT/rights_dbm`  (taken from `ht_rights.rights_current` table in the rights database)
* `ROOTDIR/data/us_cities.db` (dependency for `bib_rights.pm`)
* `ENV[us_fed_pub_exception_file]` (optional dependency for `bib_rights.pm`)

Data Out
--------

Many files are named based on the `BASENAME` variable which is "zephir_upd_YYYYMMDD." Files are typically created in
`TMPDIR` and moved/renamed from there.

AFAICT, Verifier should only be interested in files outside `TMPDIR`, with the possible exception of
`TMPDIR/vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz`.

| File                                                     | Notes                                                                                        |
| --------                                                 | -----                                                                                        |
| `CATALOG_ARCHIVE/zephir_upd_YYYYMMDD.json.gz`            | From `postZephir.pm`: gzipped and copied (not moved) by shell script                         |
| `CATALOG_PREP/zephir_upd_YYYYMMDD.json.gz`               | From `postZephir.pm`: gzipped and copied (not moved) by shell script                         |
| `CATALOG_PREP/zephir_upd_YYYYMMDD_delete.txt.gz`         | Created as `TMPDIR/BASENAME_all_delete.txt.gz` combining two files (see below)               |
| `RIGHTS_DIR/zephir_upd_YYYYMMDD.rights`                  | From `postZephir.pm`: moved from `TMPDIR`                                                    |
| `ROOTDIR/data/zephir/debug_current.txt`                  | _Commented out at end of monthly script. Should be removed._                                 |
| `TMPDIR/vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz` | Created as `TMPDIR/BASENAME_dollar_dup.txt`, renamed and sent to Zephir                      |
| `TMPDIR/zephir_upd_YYYYMMDD_delete.txt`                  | From `postZephir.pm`: usually empty list of 974-less CIDs, merged with `vufind_removed_cids` |
| `TMPDIR/zephir_upd_YYYYMMDD.rights.debug`                | From `postZephir.pm`, _if no one is using this it should be removed_                         |
| `TMPDIR/zephir_upd_YYYYMMDD_rpt.txt`                     | Log data from `postZephir.pm`                                                                |
| `TMPDIR/zephir_upd_YYYYMMDD_stderr`                      | `STDERR` from `postZephir.pm`, _if no one is using this it should be removed_                |
| `TMPDIR/zephir_upd_YYYYMMDD_zephir_delete.txt`           | Intermediate file from `vufind_removed_cids_...` before merge with our deletes, _remove?_    |


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

run_zephir_full_monthly.sh (monthly)
=============================================
* Pulls a full bib metadata file from zephir
* Moves groove_full.tsv.gz to /htapps/babel/feed/var/bibrecords
* Assembles zephir_ingested_items.txt.gz and moves to /htapps/babel/feed/var/bibrecords
* Processes the full zephir file:
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
* `zephir_full_monthly_rpt.txt`moved to ../data/full/
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
docker compose build
docker compose up -d
docker compose run --rm pz perl t/test_postZephir.t
```

For test coverage, replace the previous `docker compose run` with
```bash
docker compose run --rm pz bash -c "perl -MDevel::Cover=-silent,1 t/*.t && cover -nosummary /usr/src/app/cover_db"
```
