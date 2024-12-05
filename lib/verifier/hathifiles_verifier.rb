# frozen_string_literal: true

require "zlib"
require_relative "../verifier"
require_relative "../derivatives"

# Verifies that post_hathi workflow stage did what it was supposed to.

# TODO: document and verify the files written by monthly process.
# They should be mostly the same but need to be accounted for.

module PostZephirProcessing
  class HathifileContentsVerifier < Verifier
    HATHIFILE_FIELDS_COUNT = 26
    HATHIFILE_FIELD_REGEXES = [
      # htid - required; lowercase alphanumeric namespace, period, non-whitespace ID
      /^[a-z0-9]{2,4}\.\S+$/,
      # access - required; allow or deny
      /^(allow|deny)$/,
      # rights - required; lowercase alphanumeric plus dash and period
      /^[a-z0-9\-.]+$/,
      # ht_bib_key - required; 9 digits
      /^\d{9}$/,
      # description (enumchron) - optional; anything goes
      /^.*$/,
      # source - required; NUC/MARC organization code, all upper-case
      /^[A-Z]+$/,
      # source_bib_num - optional (see note) - no whitespace, anything else
      # allowed. Note that blank source bib nums are likely a bug in hathifiles
      # generation
      /^\S*$/,
      # oclc_num - optional; zero or more comma-separated numbers
      /^(\d+)?(,\d+)*$/,
      # hathifiles doesn't validate/normalize what comes out of the record for
      # isbn, issn, or lccn
      # isbn - optional; no whitespace, anything else goes
      /^\S*$/,
      # issn - optional; no whitespace, anything else goes
      /^\S*$/,
      # lccn - optional; no whitespace, anything else goes
      /^\S*$/,
      # title - optional (see note); anything goes
      # Note: currently blank for titles with only a 245$k; hathifiles
      # generation should likely be changed to include the k subfield.
      /^.*$/,
      # imprint - optional; anything goes
      /^.*$/,
      # rights_reason_code - required; lowercase alphabetical
      /^[a-z]+$/,
      # rights_timestamp - required; %Y-%m-%d %H:%M:%S
      /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/,
      # us_gov_doc_flag - required; 0 or 1
      /^[01]$/,
      # rights_date_used - required - numeric
      /^\d+$/,
      # publication place - required, 2 or 3 characters (but can be whitespace)
      /^.{2,3}$/,
      # lang - optional, at most 3 characters
      /^.{0,3}$/,
      # bib_fmt - required, uppercase characters
      /^[A-Z]+$/,
      # collection code - required, uppercase characters
      /^[A-Z]+$/,
      # content provider - required, lowercase characters + dash
      /^[a-z\-]+$/,
      # responsible entity code - required, lowercase characters + dash
      /^[a-z\-]+$/,
      # digitization agent code - required, lowercase characters + dash
      /^[a-z\-]+$/,
      # access profile code - required, lowercase characters + plus
      /^[a-z+]+$/,
      # author - optional, anything goes
      /^.*$/
    ]

    attr_reader :file, :line_count

    def initialize(file)
      super()
      @line_count = 0
      @file = file
    end

    def run
      Zlib::GzipReader.open(file, encoding: "utf-8").each_line do |line|
        @line_count += 1
        # limit of -1 to ensure we don't drop trailing empty fields
        fields = line.chomp.split("\t", -1)

        next unless verify_line_field_count(fields)

        verify_fields(fields)
      end
      # open file
      # check each line against a regex
      # count lines
      # also check linecount against corresponding catalog - hathifile must be >=
    end

    def verify_fields(fields)
      fields.each_with_index do |field, i|
        regex = HATHIFILE_FIELD_REGEXES[i]
        if !fields[i].match?(regex)
          error(message: "Field #{i} at line #{line_count} in #{file} ('#{field}') does not match #{regex}")
        end
      end
    end

    def verify_line_field_count(fields)
      if fields.count == HATHIFILE_FIELDS_COUNT
        true
      else
        error(message: "Line #{line_count} in #{file} has only #{fields.count} columns, expected #{HATHIFILE_FIELDS_COUNT}")
        false
      end
    end
  end

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
    def verify_hathifile(date: current_date)
      update_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_upd_YYYYMMDD.txt.gz", date: date)
      verify_file(path: update_file)
      linecount = verify_hathifile_contents(path: update_file)
      verify_hathifile_linecount(linecount, catalog_path: catalog_file_for(date))

      if date.first_of_month?
        full_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_full_YYYYMMDD.txt.gz", date: date)
        verify_file(path: full_file)
        linecount = verify_hathifile_contents(path: full_file)
        verify_hathifile_linecount(linecount, catalog_path: catalog_file_for(date, full: true))
      end
    end

    def verify_hathifile_contents(path:)
      verifier = HathifileContentsVerifier.new(path)
      verifier.run
      @errors.append(verifier.errors)
      return verifier.line_count
    end

    def verify_hathifile_linecount(linecount, catalog_path:)
      catalog_linecount = Zlib::GzipReader.open(catalog_path).count
    end

    def catalog_file_for(date, full: false)
      filetype = full ? "full" : "upd"
      self.class.dated_derivative(
        location: :CATALOG_ARCHIVE, 
        name: "zephir_#{filetype}_YYYYMMDD.json.gz", 
        date: date - 1
      )
    end

    def errors
      super.flatten
    end

  end
end
