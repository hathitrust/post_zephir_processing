# frozen_string_literal: true

require "zlib"
require_relative "../verifier"
require_relative "../derivatives"
require_relative "../derivative/dollar_dup"
require_relative "../derivative/catalog"
require_relative "../derivative/rights"

# Verifies that post_zephir workflow stage did what it was supposed to.

module PostZephirProcessing
  class PostZephirVerifier < Verifier
    attr_reader :current_date

    def run_for_date(date:)
      @current_date = date
      verify_catalog_archive
      verify_catalog_prep
      verify_dollar_dup
      verify_ingest_bibrecords
      verify_rights
    end

    # Frequency: ALL
    # Files: CATALOG_ARCHIVE/zephir_upd_YYYYMMDD.json.gz
    #   and potentially CATALOG_ARCHIVE/zephir_full_YYYYMMDD_vufind.json.gz
    # Contents: ndj file with one catalog record per line
    # Verify:
    #   readable
    #   line count must be the same as input JSON
    def verify_catalog_archive(date: current_date)
      zephir_update_path = Derivative::CatalogArchive.new(date: date, full: false).path
      if verify_file(path: zephir_update_path)
        if verify_parseable_ndj(path: zephir_update_path)
          if date.last_of_month?
            ht_bib_export_derivative_params = {
              location: :ZEPHIR_DATA,
              name: "ht_bib_export_full_YYYY-MM-DD.json.gz",
              date: date
            }
            output_path = Derivative::CatalogArchive.new(date: date, full: true).path
            verify_file(path: output_path)
            verify_parseable_ndj(path: output_path)
            output_linecount = gzip_linecount(path: output_path)

            input_path = self.class.dated_derivative(**ht_bib_export_derivative_params)
            verify_file(path: input_path)
            verify_parseable_ndj(path: input_path)
            input_linecount = gzip_linecount(path: input_path)

            if output_linecount != input_linecount
              error(
                message: sprintf(
                  "output line count (%s = %s) != input line count (%s = %s)",
                  output_path,
                  output_linecount,
                  input_path,
                  input_linecount
                )
              )
            end
          end
        end
      end
    end

    # Frequency: ALL
    # Files: CATALOG_PREP/zephir_upd_YYYYMMDD.json.gz and CATALOG_PREP/zephir_upd_YYYYMMDD_delete.txt.gz
    #   and potentially CATALOG_PREP/zephir_full_YYYYMMDD_vufind.json.gz
    # Contents:
    #   json.gz files: ndj with one catalog record per line
    #   delete.txt.gz: see `#verify_deletes_contents`
    # Verify:
    #   readable
    #   TODO: deletes file is combination of two component files in TMPDIR?
    def verify_catalog_prep(date: current_date)
      delete_file = Derivative::Delete.new(date: date, full: false)
      if verify_file(path: delete_file.path)
        verify_deletes_contents(path: delete_file.path)
      end

      Derivative::CatalogPrep.derivatives_for_date(date: date).each do |derivative|
        verify_file(path: derivative.path)
      end
    end

    # Verify contents of the given file consists of catalog record IDs (9 digits)
    # or blank lines
    def verify_deletes_contents(path:)
      Zlib::GzipReader.open(path).each_line do |line|
        if line != "\n" && !line.match?(/^\d{9}$/)
          error message: "Unexpected line in #{path} (was '#{line.strip}'); expecting catalog record ID (9 digits)"
        end
      end
    end

    # Frequency: DAILY
    # Files: TMPDIR/vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz
    #
    # Contents:
    #
    # Historically, un-dollarized uc1 HTIDs (e.g., uc1.b312920) one per line.
    # These files originally served as a way to report back to Zephir on items to
    # "uningest" related to a change that University of California made
    # regarding certain barcode ranges -- things like uc1.b312920 moved to
    # uc1.$b312920, and we needed to 'uningest' uc1.b312920.
    #
    # Later, it served as a more general way to cause Zephir to mark items as not
    # ingested and thereby no longer export them in full files. This
    # functionality (as of 2024) has not been used in many years. If we at some
    # point begin fully deleting material from the repository, this
    # functionality could again be used.
    #
    # As of December 2024, these files are generated each day, but are expected
    # to be empty.
    #
    # Verify:
    #  readable
    #  empty
    def verify_dollar_dup(date: current_date)
      dollar_dup = Derivative::DollarDup.new(date: date).path
      if verify_file(path: dollar_dup)
        gz_count = gzip_linecount(path: dollar_dup)
        if gz_count.positive?
          error message: "spurious dollar_dup lines: #{dollar_dup} should be empty (found #{gz_count} lines)"
        end
      end
    end

    # Frequency: MONTHLY
    # Files:
    #   INGEST_BIBRECORDS/groove_full.tsv.gz
    #   INGEST_BIBRECORDS/zephir_ingested_items.txt.gz
    # Contents: TODO
    # Verify: readable
    def verify_ingest_bibrecords(date: current_date)
      if date.last_of_month?
        verify_file(path: self.class.derivative(location: :INGEST_BIBRECORDS, name: "groove_full.tsv.gz"))
        verify_file(path: self.class.derivative(location: :INGEST_BIBRECORDS, name: "zephir_ingested_items.txt.gz"))
      end
    end

    # Frequency: BOTH
    # Files:
    #   RIGHTS_ARCHIVE/zephir_upd_YYYYMMDD.rights (daily)
    #   RIGHTS_ARCHIVE/zephir_full_YYYYMMDD.rights (monthly)
    # Contents: see verify_rights_file_format
    # Verify:
    #   readable
    #   accepted by verify_rights_file_format
    def verify_rights(date: current_date)
      Derivative::Rights.derivatives_for_date(date: date).each do |derivative|
        path = derivative.path
        if verify_file(path: path)
          verify_rights_file_format(path: path)
        end
      end
    end

    # Rights file must:
    # * exist & be be readable (both covered by verify_rights)
    # * either be empty, or all its lines must match regex.
    def verify_rights_file_format(path:)
      line_regex = /^ [a-z0-9]+ \. [a-z0-9:\/\$\.]+ # col 1, namespace.objid
              \t (ic|pd|pdus|und)              # col 2, one of these
              \t bib                           # col 3, exactly this
              \t bibrights                     # col 4, exactly this
              \t [a-z]+(-[a-z]+)*              # col 5, digitization source, e.g. 'ia', 'cornell-ms'
              $/x

      # A column-by column version of line_regex
      column_regexes = [
        {name: :id, regex: /^[a-z0-9]+\.[a-z0-9:\/\$\.]+s$/},
        {name: :rights, regex: /^(ic|pd|pdus|und)$/},
        {name: :bib, regex: /^bib$/},
        {name: :bibrights, regex: /^bibrights$/},
        {name: :digitization_source, regex: /^[a-z]+(-[a-z]+)*$/}
      ]

      # This allows an empty file as well, which is possible.
      File.open(path) do |f|
        f.each_line.with_index do |line, i|
          line.chomp!
          unless line.match?(line_regex)
            # If line_regex did not match the line, find the offending col(s) and report
            cols = line.split("\t", -1)
            cols.each_with_index do |col, j|
              unless col.match?(column_regexes[j][:regex])
                error message: "Rights file #{path}:#{i + 1}, invalid column #{column_regexes[j][:name]} : #{col}"
              end
            end
          end
        end
      end
    end
  end
end
