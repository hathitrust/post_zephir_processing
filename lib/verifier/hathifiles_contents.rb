# frozen_string_literal: true

require "zlib"
require "verifier"

# Verifies that hathifiles workflow stage did what it was supposed to.

module PostZephirProcessing
  class Verifier::HathifileContents < Verifier
    HATHIFILE_FIELD_SPECS = [
      # htid - required; lowercase alphanumeric namespace, period, non-whitespace ID
      {name: "htid", regex: /^[a-z0-9]{2,4}\.\S+$/},
      # access - required; allow or deny
      {name: "access", regex: /^(allow|deny)$/},
      # rights - required; lowercase alphanumeric plus dash and period
      {name: "rights", regex: /^[a-z0-9\-.]+$/},
      # ht_bib_key - required; 9 digits
      {name: "ht_bib_key", regex: /^\d{9}$/},
      # description (enumchron) - optional; anything goes
      {name: "description", regex: /^.*$/},
      # source - required; NUC/MARC organization code, all upper-case
      {name: "source", regex: /^[A-Z]+$/},
      # source_bib_num - optional (see note) - no whitespace, anything else
      # allowed. Note that blank source bib nums are likely a bug in hathifiles
      # generation
      {name: "source_bib_num", regex: /^\S*$/},
      # oclc_num - optional; zero or more comma-separated numbers
      {name: "oclc_num", regex: /^(\d+)?(,\d+)*$/},
      # hathifiles doesn't validate/normalize what comes out of the record for
      # isbn, issn, or lccn
      # isbn - optional; anything goes
      {name: "hathifiles", regex: /^.*$/},
      # issn - optional; anything goes
      {name: "issn", regex: /^.*$/},
      # lccn - optional; anything goes
      {name: "lccn", regex: /^.*$/},
      # title - optional (see note); anything goes
      # Note: currently blank for titles with only a 245$k; hathifiles
      # generation should likely be changed to include the k subfield.
      {name: "title", regex: /^.*$/},
      # imprint - optional; anything goes
      {name: "imprint", regex: /^.*$/},
      # rights_reason_code - required; lowercase alphabetical
      {name: "rights_reason_code", regex: /^[a-z]+$/},
      # rights_timestamp - required; %Y-%m-%d %H:%M:%S
      {name: "rights_timestamp", regex: /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/},
      # us_gov_doc_flag - required; 0 or 1
      {name: "us_gov_doc_flag", regex: /^[01]$/},
      # rights_date_used - required - numeric
      {name: "rights_date_used", regex: /^\d+$/},
      # publication place - required, 2 or 3 characters (but can be whitespace)
      {name: "pub_place", regex: /^.{2,3}$/},
      # lang - optional, at most 3 characters
      {name: "lang", regex: /^.{0,3}$/},
      # bib_fmt - required, uppercase characters
      {name: "bib_fmt", regex: /^[A-Z]+$/},
      # collection code - required, uppercase characters
      {name: "collection_code", regex: /^[A-Z]+$/},
      # content provider - required, lowercase characters + dash
      {name: "content_provider_code", regex: /^[a-z\-_]+$/},
      # responsible entity code - required, lowercase characters + dash
      {name: "responsible_entity_code", regex: /^[a-z-]+$/},
      # digitization agent code - required, lowercase characters + dash and optional trailing digit (yale2)
      {name: "digitization_agent_code", regex: /^[a-z-]+\d?$/},
      # access profile code - required, lowercase characters + plus
      {name: "access_profile_code", regex: /^[a-z+]+$/},
      # author - optional, anything goes
      {name: "author", regex: /^.*$/}
    ]

    attr_reader :file, :line_count

    def initialize(file)
      super()
      @line_count = 0
      @file = file
    end

    def run
      info message: "verifying contents of #{file}"
      Zlib::GzipReader.open(file, encoding: "utf-8").each_line do |line|
        @line_count += 1
        # limit of -1 to ensure we don't drop trailing empty fields
        fields = line.chomp.split("\t", -1)

        next unless verify_line_field_count(fields)

        verify_fields(fields)
      end
    end

    def verify_fields(fields)
      fields.zip(HATHIFILE_FIELD_SPECS).each do |field_value, field_spec|
        field_name = field_spec[:name]
        regex = field_spec[:regex]
        if !field_value.match?(regex)
          error(message: "Field #{field_name} at line #{line_count} in #{file} ('#{field_value}') does not match #{regex}")
        end
      end
    end

    def verify_line_field_count(fields)
      if fields.count == HATHIFILE_FIELD_SPECS.count
        true
      else
        error(message: "Line #{line_count} in #{file} has only #{fields.count} columns, expected #{HATHIFILE_FIELD_SPECS.count}")
        false
      end
    end
  end
end
