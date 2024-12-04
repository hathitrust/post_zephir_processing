# frozen_string_literal: true

require "climate_control"
require "zlib"
require "verifier/hathifiles_verifier"
require "tempfile"
require "logger"

module PostZephirProcessing
  RSpec.describe(HathifilesVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    describe "#verify_hathifiles_count" do
      context "with a catalog json file with 5 records" do
        it "accepts a hathifile with 5 records"
        it "accepts a hathifile with 10 records"
        it "rejects a hathifile with 4 records"
        it "rejects a hathifile with no records"
      end
    end

    hathifiles_fields = [
      {
        name: "htid",
        good: "mdp.39015031446076",
        bad: "this is not an id",
        optional: false
      },
      {
        name: "access",
        good: "deny",
        bad: "nope",
        optional: false
      },
      {
        name: "rights",
        good: "ic",
        bad: "In Copyright",
        optional: false
      },
      {
        name: "ht_bib_key",
        good: "000000400",
        bad: "not a bib key",
        optional: false
      },
      {
        name: "description",
        good: "Jun-Oct 1927",
        optional: true
      },
      {
        name: "source",
        good: "MIU",
        bad: "this is not a NUC code",
        optional: false
      },
      {
        name: "source_bib_num",
        good: "990000003710106381",
        bad: "this is not a source bib num",
        # this can be empty if the record has an sdrnum like sdr-osu(OCoLC)6776655 which the regex at https://github.com/hathitrust/hathifiles/blob/af5e4ff682fb81165e6232a1151cfbeeacfdfd21/lib/bib_record.rb#L160C34-L160C50 doesn't match, probably a bug in hathifiles
        optional: true
      },

      {
        name: "oclc_num",
        good: "217079596,55322",
        bad: "this is not an OCLC number",
        optional: true
      },

      # isbn, issn, lccn come straight from the record w/o additional
      # validation in hathifiles, probably not worth doing add'l validation
      # here
      {
        name: "isbn",
        good: "9789679430011,9679430014",
        optional: true
      },
      {
        name: "issn",
        good: "0084-9499,00113344",
        optional: true
      },
      {
        name: "lccn",
        good: "",
        optional: true
      },

      {
        name: "title",
        good: "",
        # this can be empty if the record only has a 245$k. that's probably a bug in the
        # hathifiles which we should fix.
        optional: true
      },
      {
        name: "imprint",
        good: "Pergamon Press [1969]",
        optional: true
      },
      {
        name: "rights_reason_code",
        good: "bib",
        bad: "not a reason code",
        optional: false
      },
      {
        name: "rights_timestamp",
        good: "2008-06-01 09:30:17",
        bad: "last thursday",
        optional: false
      },
      {
        name: "us_gov_doc_flag",
        good: "0",
        bad: "not a gov doc flag",
        optional: false
      },
      {
        name: "rights_date_used",
        good: "1987",
        bad: "this is not a year",
        optional: false
      },
      {
        name: "pub_place",
        good: "miu",
        bad: "not a publication place",
        optional: false
      },
      {
        name: "lang",
        good: "eng",
        bad: "not a language code",
        optional: true
      },
      {
        name: "bib_fmt",
        good: "BK",
        bad: "not a bib fmt",
        optional: false
      },
      {
        name: "collection_code",
        good: "MIU",
        bad: "not a collection code",
        optional: false
      },
      {
        name: "content_provider_code",
        good: "umich",
        bad: "not an inst id",
        optional: false
      },
      {
        name: "responsible_entity_code",
        good: "umich",
        bad: "not an inst id",
        optional: false
      },
      {
        name: "digitization_agent_code",
        good: "google",
        bad: "not an inst id",
        optional: false
      },
      {
        name: "access_profile_code",
        good: "open",
        bad: "not an access profile",
        optional: false
      },
      {
        name: "author",
        good: "Chaucer, Geoffrey, -1400.",
        optional: true
      }
    ]

    describe "#verify_hathifile_contents" do
      let(:sample_line) { File.read(fixture("sample_hathifile_line.txt"), encoding: "utf-8") }
      let(:sample_fields) { sample_line.split("\t") }

      it "accepts a file with a single real hathifiles entry" do
        expect_ok(:verify_hathifile_contents, sample_line, gzipped: true)
      end

      it "rejects a file where some lines have less than #{hathifiles_fields.count} tab-separated columns" do
        contents = sample_line + "mdp.35112100003484\tdeny\n"
        expect_not_ok(:verify_hathifile_contents, contents, errmsg: /.*columns.*/, gzipped: true)
      end

      hathifiles_fields.each_with_index do |field, i|
        it "accepts a file with #{field[:name]} matching the regex" do
          sample_fields[i] = field[:good]
          contents = sample_fields.join("\t")

          expect_ok(:verify_hathifile_contents, contents, gzipped: true)
        end

        if field.has_key?(:bad)
          it "rejects a file with #{field[:name]} not matching the regex" do
            sample_fields[i] = field[:bad]
            contents = sample_fields.join("\t")

            expect_not_ok(:verify_hathifile_contents, contents,
              errmsg: /Field #{i}.*does not match/, gzipped: true)
          end
        end

        if field[:optional]
          it "accepts a file with empty #{field[:name]}" do
            sample_fields[i] = ""
            contents = sample_fields.join("\t")

            expect_ok(:verify_hathifile_contents, contents, gzipped: true)
          end
        else
          it "rejects a file with empty #{field[:name]}" do
            sample_fields[i] = ""
            contents = sample_fields.join("\t")

            expect_not_ok(:verify_hathifile_contents, contents,
              errmsg: /Field #{i}.*does not match/, gzipped: true)
          end
        end
      end
    end

    describe "#catalog_file_for" do
      it "computes a source catalog file based on date - 1"
    end
  end
end
