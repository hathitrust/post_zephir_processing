# Potential Problems Encountered
The following is an attempt at a comprehensive list of **expected** errors that might be reported in the course of running the daily cronjobs.

They can best be summarised as
  1. missing mounting locations on the server
  2. inability to retrieve source data from Zephir

Of course, other errors are possible, especially if substantive changes are made to the shell or perl dependencies. Errors which don't result in a very apparent crash are largely undetectable, as expected behavior is so poorly defined. If they were knowable, this would have been rewritten long ago.

---

## run_process_zephir_incremental.sh
* Unable to get ht_bib_export_incr_<date>.json.gz from zephir (reports)
* Unable to **find** ht_bib_export_incr_<date>.json.gz (exits)
* Unable to retrieve or find vufind_removed_cids_<date>.txt.gz (exits)
* Unable to cp zephir_upd_<date>.json.gz to /htsolr/catalog/prep (exits)
* Unable to cp zephir_upd_<date>_all_delete.txt.gz to /htsolr/catalog/prep (exits)
* Unable to send zephir_upd_dollar_up.txt.gz to Zephir (exits)
---

## run_zephir_full_monthly.sh
Some of these seem silly.
* Failure to retrieve groove_export_<date>.tsv.gz (exits)
* Failure to retrieve ht_bib_export_full_<date>.json.gz from zephir (exits)
* Unable to concatenate processed files into zephir_ingested_items.txt.gz (reports)
* Unable to concatenate to zephir_full_<date>_vufind.json.gz (reports)
* Unable to transfer zephir_full_<date>_vufind.json.gz to /htsolr/catalog/prep (reports)
* Unable to concatenate zephir_full_monthly_??.rights to zephir_full_<date>.rights (reports)
* Unable to concatenate zephir_full_monthly_??.rights.debug (reports)
* Unable to concatenate zephir_full_monthly_??.rights_rpt.tsv to zephir_full_<date>.rights_rpt.tsv (reports)
* Unable to concatenate zephir_full_monthly_??_out.rpt.txt to zephir_full_monthly_rpt.txt (reports)
