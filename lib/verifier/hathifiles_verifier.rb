# frozen_string_literal: true

require "zlib"
require "verifier"
require "verifier/hathifiles_contents_verifier"
require "derivative/hathifile"

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
      Derivative::Hathifile.derivatives_for_date(date: date).each do |derivative|
        path = derivative.path
        next unless verify_file(path: path)
        contents_verifier = verify_hathifile_contents(path: path)
        catalog_path = Derivative::CatalogArchive.new(date: date - 1, full: derivative.full).path
        verify_hathifile_linecount(contents_verifier.line_count, catalog_path: catalog_path)
      end
    end

    def verify_hathifile_linecount(linecount, catalog_path:)
      catalog_linecount = gzip_linecount(path: catalog_path)
      if linecount < catalog_linecount
        error(message: "#{catalog_path} has #{catalog_linecount} records but corresponding hathifile only has #{linecount}")
      end
    end

    def errors
      super.flatten
    end

    private

    def verify_hathifile_contents(path:)
      HathifileContentsVerifier.new(path).tap do |contents_verifier|
        contents_verifier.run
        @errors.append(contents_verifier.errors)
      end
    end
  end
end
