# frozen_string_literal: true

require "zlib"
require_relative "hathifiles_contents_verifier"
require_relative "../verifier"
require_relative "../derivatives"

# Verifies that hathifiles workflow stage did what it was supposed to.

module PostZephirProcessing
  class HathifilesVerifier < Verifier
    attr_reader :current_date

    def run_for_date(date:)
      @current_date = date
      verify_hathifile
    end

    # /htapps/archive/hathifiles/hathi_upd_20240201.txt.gz or hathi_full_20241201.txt.gz
    #
    # Frequency: ALL
    # Files: CATALOG_PREP/hathi_upd_YYYYMMDD.txt.gz
    #   and potentially HATHIFILE_ARCHIVE/hathi_full_YYYYMMDD.txt.gz
    # Contents: verified with HathifileContentsVerifier with regexes for each line/field
    # Verify:
    #   readable
    def verify_hathifile(date: current_date)
      update_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_upd_YYYYMMDD.txt.gz", date: date)
      if verify_file(path: update_file)
        linecount = verify_hathifile_contents(path: update_file)
        verify_hathifile_linecount(linecount, catalog_path: catalog_file_for(date))
      end

      # first of month
      if date.first_of_month?
        full_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_full_YYYYMMDD.txt.gz", date: date)
        if verify_file(path: full_file)
          linecount = verify_hathifile_contents(path: full_file)
          verify_hathifile_linecount(linecount, catalog_path: catalog_file_for(date, full: true))
        end
      end
    end

    def verify_hathifile_contents(path:)
      verifier = HathifileContentsVerifier.new(path)
      verifier.run
      @errors.append(verifier.errors)
      verifier.line_count
    end

    def verify_hathifile_linecount(linecount, catalog_path:)
      catalog_linecount = gzip_linecount(path: catalog_path)
      if linecount < catalog_linecount
        error(message: "#{catalog_path} has #{catalog_linecount} records but corresponding hathifile only has #{linecount}")
      end
    end

    def catalog_file_for(date, full: false)
      # TODO address this somehow with Derivative. Maybe Derivative should know
      # how to construct the filenames?
      name = if full
        "zephir_full_YYYYMMDD_vufind.json.gz"
      else
        "zephir_upd_YYYYMMDD.json.gz"
      end

      self.class.dated_derivative(
        location: :CATALOG_ARCHIVE,
        name: name,
        date: date - 1
      )
    end

    def errors
      super.flatten
    end
  end
end
