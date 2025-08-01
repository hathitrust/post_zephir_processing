# frozen_string_literal: true

require "open3"
require "zlib"
require "verifier"
require "post_zephir_derivatives"
require "derivative/dollar_dup"
require "derivative/catalog"
require "derivative/rights"
require "derivative/ingest_bibrecord"
require "derivative/ht_bib_export"

# Verifies that post_zephir workflow stage did what it was supposed to.

module PostZephirProcessing
  class Verifier::PostZephir < Verifier
    attr_reader :current_date

    def run_for_date(date:)
      super
      @current_date = date
      verify_catalog_archive
      verify_catalog_prep
      verify_dollar_dup
      verify_ingest_bibrecords
      verify_rights
    end

    # Frequency: ALL
    # Files:
    #   CATALOG_ARCHIVE/zephir_upd_YYYYMMDD.json.gz
    #   CATALOG_ARCHIVE/zephir_full_YYYYMMDD_vufind.json.gz [Monthly]
    # Contents: ndj file with one catalog record per line
    # Verify:
    #   readable
    #   line count must be the same as input JSON minus suppressed records,
    #     which are only detectable in the monthly logfile as it's the only
    #     one that is moved to a proper storage location
    def verify_catalog_archive(date: current_date)
      Derivative::CatalogArchive.derivatives_for_date(date: date).each do |derivative|
        next unless verify_file(path: derivative.path)

        verify_parseable_ndj(path: derivative.path)
        archive_linecount = gzip_linecount(path: derivative.path)
        bib_export_path = Derivative::HTBibExport.new(date: date, full: derivative.full?).path
        next unless verify_file(path: bib_export_path)

        bib_export_linecount = gzip_linecount(path: bib_export_path)
        expected_delta = count_suppressed_records(derivative: derivative)
        if bib_export_linecount != archive_linecount + expected_delta
          error(
            message: sprintf(
              "catalog archive line count (%s = %s + %s) != bib export line count (%s = %s)",
              derivative.path,
              archive_linecount,
              expected_delta,
              bib_export_path,
              bib_export_linecount
            )
          )
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
      delete_file = Derivative::Delete.new(date: date)

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
      info message: "verifying contents of #{path}"
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
      return unless verify_file(path: dollar_dup)
      gz_count = gzip_linecount(path: dollar_dup)
      if gz_count.positive?
        error message: "spurious dollar_dup lines: #{dollar_dup} should be empty (found #{gz_count} lines)"
      end
    end

    # Frequency: MONTHLY
    # Files:
    #   INGEST_BIBRECORDS/groove_full.tsv.gz
    #   INGEST_BIBRECORDS/zephir_ingested_items.txt.gz
    # Contents: TODO
    # Verify: readable
    def verify_ingest_bibrecords(date: current_date)
      Derivative::IngestBibrecord.derivatives_for_date(date: date).each do |derivative|
        verify_file(path: derivative.path)
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
        next unless verify_file(path: path)
        verify_rights_file_format(path: path)
      end
    end

    # Rights file must:
    # * exist & be be readable (both covered by verify_rights)
    # * either be empty, or all its lines must match regex.
    def verify_rights_file_format(path:)
      # A column-by column version of line_regex
      column_regexes = [
        # col 1, namespace.objid
        {name: :id, regex: /^[a-z0-9]+\.\S+$/},
        # col 2, one of these
        {name: :rights, regex: /^(ic|pd|pdus|und)$/},
        # col 3, exactly this
        {name: :bib, regex: /^bib$/},
        # col 4, exactly this
        {name: :bibrights, regex: /^bibrights$/},
        # col 5, e.g. 'ia', 'cornell-ms', 'yale2'
        {name: :digitization_source, regex: /^[a-z\d]+(-[a-z\d]+)*$/}
      ]

      info message: "verifying contents of #{path}"
      # This allows an empty file as well, which is possible.
      File.open(path) do |f|
        f.each_line.with_index do |line, i|
          line.chomp!
          cols = line.split("\t", -1)
          cols.each_with_index do |col, j|
            unless col.match?(column_regexes[j][:regex])
              error message: "Rights file #{path}:#{i + 1}, invalid column #{column_regexes[j][:name]} : #{col}"
            end
          end
        end
      end
    end

    private

    def verify_hathifile_contents(path:)
      HathifileContentsVerifier.new(path).tap do |contents_verifier|
        contents_verifier.run
        @errors.append(contents_verifier.errors)
      end
    end

    # Count the number of suppressed records that will be a discrepancy between
    # catalog prep file and zephir file line counts.
    # Records with all HTID rights set to e.g. supp/* do not get included in certain
    # downstream activities, e.g. hathifiles and catalog indexing.
    # Only applies to monthly files.
    GREP_ERR = 2
    def count_suppressed_records(derivative:)
      if derivative.full?
        if File.exist?(zephir_full_monthly_rpt_txt)
          cmd = "grep -c no.unsuppressed.*not.written #{zephir_full_monthly_rpt_txt}"
          stdout_str, stderr_str, status = Open3.capture3(cmd)
          if status.exitstatus >= GREP_ERR
            error message: "count_suppressed_records: status #{status.exitstatus}, STDERR '#{stderr_str.chomp}' (#{cmd})"
          else
            # With the -c option we should reliably just get a number from STDOUT
            return stdout_str.chomp.to_i
          end
        end
      end
      0
    end

    # This is a non-datestamped file written by postZephir.pm and moved into position
    # by run_zephir_full_monthly.sh` (around line 150)
    def zephir_full_monthly_rpt_txt
      @zephir_full_monthly_rpt_txt ||= File.join(ENV["ZEPHIR_DATA"], "full", "zephir_full_monthly_rpt.txt")
    end
  end
end
