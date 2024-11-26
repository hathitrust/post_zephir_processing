# frozen_string_literal: true

require_relative "../verifier"
require_relative "../derivatives"

# Verifies that post_zephir workflow stage did what it was supposed to.

# TODO: document and verify the files written by monthly process.
# They should be mostly the same but need to be accounted for.

module PostZephirProcessing
  class PostZephirVerifier < Verifier
    attr_reader :current_date

    def run_for_date(date:)
      @current_date = date
      verify_catalog_archive
      verify_catalog_prep
      verify_dollar_dup
      verify_groove_export
      verify_ingest_bibrecords
      verify_rights
      verify_zephir_data
    end

    # Frequency: ALL
    # Files: CATALOG_PREP/zephir_upd_YYYYMMDD.json.gz
    #   and potentially CATALOG_ARCHIVE/zephir_full_YYYYMMDD_vufind.json.gz
    # Contents: TODO
    # Verify:
    #   readable
    #   TODO: line count must be the same as input JSON
    def verify_catalog_archive(date: current_date)
      verify_file(path: self.class.dated_derivative(location: :CATALOG_ARCHIVE, name: "zephir_upd_YYYYMMDD.json.gz", date: date))
      if date.last_of_month?
        verify_file(path: self.class.dated_derivative(location: :CATALOG_ARCHIVE, name: "zephir_full_YYYYMMDD_vufind.json.gz", date: date))
      end
    end

    # Frequency: ALL
    # Files: CATALOG_PREP/zephir_upd_YYYYMMDD.json.gz and CATALOG_PREP/zephir_upd_YYYYMMDD_delete.txt.gz
    #   and potentially CATALOG_PREP/zephir_full_YYYYMMDD_vufind.json.gz
    # Contents: TODO
    # Verify:
    #   readable
    #   TODO: deletes file is combination of two component files in TMPDIR?
    def verify_catalog_prep(date: current_date)
      verify_file(path: self.class.dated_derivative(location: :CATALOG_PREP, name: "zephir_upd_YYYYMMDD.json.gz", date: date))
      verify_file(path: self.class.dated_derivative(location: :CATALOG_PREP, name: "zephir_upd_YYYYMMDD_delete.txt.gz", date: date))
      if date.last_of_month?
        verify_file(path: self.class.dated_derivative(location: :CATALOG_PREP, name: "zephir_full_YYYYMMDD_vufind.json.gz", date: date))
      end
    end

    # Frequency: DAILY
    # Files: TMPDIR/vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz
    # Contents: TODO
    # Verify:
    #  readable
    #  empty
    def verify_dollar_dup(date: current_date)
      dollar_dup = self.class.dated_derivative(location: :TMPDIR, name: "vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz", date: date)
      if verify_file(path: dollar_dup)
        Zinzout.zin(dollar_dup) do |infile|
          if infile.count.positive?
            error "#{dollar_dup} has #{infile.count} lines, should be 0"
          end
        end
      end
    end

    # Frequency: MONTHLY
    # Files: INGEST_BIBRECORDS/groove_full.tsv.gz
    # Contents: TODO
    # Verify: readable
    def verify_groove_export(date: current_date)
      if date.last_of_month?
        verify_file(path: self.class.derivative(location: :INGEST_BIBRECORDS, name: "groove_full.tsv.gz"))
      end
    end

    # Frequency: MONTHLY
    # Files: INGEST_BIBRECORDS/groove_full.tsv.gz, INGEST_BIBRECORDS/zephir_ingested_items.txt.gz
    # Contents: TODO
    # Verify: readable
    def verify_ingest_bibrecords(date: current_date)
      if date.last_of_month?
        verify_file(path: self.class.derivative(location: :INGEST_BIBRECORDS, name: "groove_full.tsv.gz"))
        verify_file(path: self.class.derivative(location: :INGEST_BIBRECORDS, name: "zephir_ingested_items.txt.gz"))
      end
    end

    # Frequency: BOTH
    # Files: RIGHTS_ARCHIVE/zephir_upd_YYYYMMDD.rights
    #   and potentially RIGHTS_ARCHIVE/zephir_full_YYYYMMDD.rights
    # Contents: TODO
    # Verify:
    #   readable
    #   TODO: compare each line against a basic regex
    def verify_rights(date: current_date)
      verify_file(path: self.class.dated_derivative(location: :RIGHTS_ARCHIVE, name: "zephir_upd_YYYYMMDD.rights", date: date))
      if date.last_of_month?
        verify_file(path: self.class.dated_derivative(location: :RIGHTS_ARCHIVE, name: "zephir_full_YYYYMMDD.rights", date: date))
      end
    end

    # Frequency: MONTHLY
    # Files: ZEPHIR_DATA/full/zephir_full_monthly_rpt.txt, ZEPHIR_DATA/full/zephir_full_YYYYMMDD.rights_rpt.tsv
    # Contents: TODO
    # Verify: readable
    def verify_zephir_data(date: current_date)
      if date.last_of_month?
        verify_file(path: self.class.derivative(location: :ZEPHIR_DATA, name: "full/zephir_full_monthly_rpt.txt"))
        verify_file(path: self.class.dated_derivative(location: :ZEPHIR_DATA, name: "full/zephir_full_YYYYMMDD.rights_rpt.tsv", date: date))
      end
    end
  end
end
