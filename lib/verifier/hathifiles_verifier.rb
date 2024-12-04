# frozen_string_literal: true

require "zlib"
require_relative "../verifier"
require_relative "../derivatives"

# Verifies that post_hathi workflow stage did what it was supposed to.

# TODO: document and verify the files written by monthly process.
# They should be mostly the same but need to be accounted for.

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
    # Contents: TODO
    # Verify:
    #   readable
    #   TODO: line count must be > than corresponding catalog file
    #   TODO: regex format
    def verify_hathifile_presence(date: current_date)
      update_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_upd_YYYYMMDD.txt.gz", date: date)
      verify_file(path: update_file)
      verify_hathifile_contents(update_file)

      if date.first_of_month?
        full_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_full_YYYYMMDD.txt.gz", date: date)
        verify_file(path: full_file)
        verify_hathifile_contents(full_file)
      end
    end

    def verify_hathifile_contents(file)
      # open file
      # check each line against a regex
      # count lines
      # also check linecount against corresponding catalog - hathifile must be >=
    end
  end
end
