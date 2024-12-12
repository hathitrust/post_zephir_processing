# frozen_string_literal: true

require "zlib"
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
    def verify_catalog_archive(date: current_date)
      zephir_update_derivative_params = {
        location: :CATALOG_ARCHIVE,
        name: "zephir_upd_YYYYMMDD.json.gz",
        date: date
      }
      verify_file(path: self.class.dated_derivative(**zephir_update_derivative_params))

      if date.last_of_month?
        zephir_full_derivative_params = {
          location: :CATALOG_ARCHIVE,
          name: "zephir_full_YYYYMMDD_vufind.json.gz",
          date: date
        }

        ht_bib_export_derivative_params = {
          location: :ZEPHIR_DATA,
          name: "ht_bib_export_full_YYYY-MM-DD.json.gz",
          date: date
        }

        output_path = self.class.dated_derivative(**zephir_full_derivative_params)
        verify_file(path: output_path)
        output_linecount = gzip_linecount(path: output_path)

        input_path = self.class.dated_derivative(**ht_bib_export_derivative_params)
        verify_file(path: input_path)
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

    # Frequency: ALL
    # Files: CATALOG_PREP/zephir_upd_YYYYMMDD.json.gz and CATALOG_PREP/zephir_upd_YYYYMMDD_delete.txt.gz
    #   and potentially CATALOG_PREP/zephir_full_YYYYMMDD_vufind.json.gz
    # Contents: TODO
    # Verify:
    #   readable
    #   TODO: deletes file is combination of two component files in TMPDIR?
    def verify_catalog_prep(date: current_date)
      delete_file = self.class.dated_derivative(location: :CATALOG_PREP, name: "zephir_upd_YYYYMMDD_delete.txt.gz", date: date)
      verify_file(path: self.class.dated_derivative(location: :CATALOG_PREP, name: "zephir_upd_YYYYMMDD.json.gz", date: date))
      verify_file(path: delete_file)
      verify_deletes_contents(path: delete_file)
      if date.last_of_month?
        verify_file(path: self.class.dated_derivative(location: :CATALOG_PREP, name: "zephir_full_YYYYMMDD_vufind.json.gz", date: date))
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
      upd_path = self.class.dated_derivative(location: :RIGHTS_ARCHIVE, name: "zephir_upd_YYYYMMDD.rights", date: date)
      verify_file(path: upd_path)
      verify_rights_file_format(path: upd_path)

      if date.last_of_month?
        full_path = self.class.dated_derivative(location: :RIGHTS_ARCHIVE, name: "zephir_full_YYYYMMDD.rights", date: date)
        verify_file(path: full_path)
        verify_rights_file_format(path: full_path)
      end
    end

    # Rights file must:
    # * exist & be be readable (both covered by verify_rights)
    # * either be empty, or all its lines must match regex.
    def verify_rights_file_format(path:)
      regex = /^ [a-z0-9]+ \. [a-z0-9:\/\$\.]+ # col 1, namespace.objid
              \t (ic|pd|pdus|und)              # col 2, one of these
              \t bib                           # col 3, exactly this
              \t bibrights                     # col 4, exactly this
              \t [a-z]+(-[a-z]+)*              # col 5, digitization source, e.g. 'ia', 'cornell-ms'
              $/x

      # This allows an empty file as well, which is possible.
      File.open(path) do |f|
        f.each_line do |line|
          line.strip!
          unless line.match?(regex)
            error message: "Rights file #{path} contains malformed line: #{line}"
          end
        end
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
