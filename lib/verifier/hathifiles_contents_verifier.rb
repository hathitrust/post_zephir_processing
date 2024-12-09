# frozen_string_literal: true

require "zlib"
require_relative "../verifier"

# Verifies that hathifiles workflow stage did what it was supposed to.

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
      # isbn - optional; anything goes
      /^.*$/,
      # issn - optional; anything goes
      /^.*$/,
      # lccn - optional; anything goes
      /^.*$/,
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
end
