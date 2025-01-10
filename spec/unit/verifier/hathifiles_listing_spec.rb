# frozen_string_literal: true

require "verifier/hathifiles_listing"
require "derivative/hathifile_www"

module PostZephirProcessing
  RSpec.describe(Verifier::HathifilesListing) do
    # Using secondday here as a representative for
    # "any day of the month that's not the 1st"
    # missingday does not have files or listings
    firstday = Date.parse("2023-01-01")
    secondday = Date.parse("2023-01-02")
    missingday_first = Date.parse("2020-01-01")
    missingday_second = Date.parse("2020-01-02")

    firstday_ymd = firstday.strftime("%Y%m%d")
    secondday_ymd = secondday.strftime("%Y%m%d")
    missingday_first_ymd = missingday_first.strftime("%Y%m%d")
    missingday_second_ymd = missingday_second.strftime("%Y%m%d")

    fixture("hathi_file_list.json")

    let(:verifier) { described_class.new }

    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          WWW_DIR: fixture("www"),
          HATHIFILE_ARCHIVE: fixture("hathifile_archive")
        ) do
          example.run
        end
      end
    end

    describe "#verify_hathifiles_listing" do
      it "finds update and full file on firstday" do
        verifier.verify_hathifiles_listing(date: firstday)
        expect(verifier.errors).to eq []
      end

      it "finds just an update file on secondday" do
        verifier.verify_hathifiles_listing(date: secondday)
        expect(verifier.errors).to eq []
      end

      it "produces 4 errors if upd and full file are missing on the first day of the month + no listing" do
        verifier.verify_hathifiles_listing(date: missingday_first)
        expect(verifier.errors.count).to eq 4 # 2 files not found, 2 listings not found
        expect(verifier.errors).to include(/No listing with filename: hathi_upd_#{missingday_first_ymd}.txt.gz .+/)
        expect(verifier.errors).to include(/not found: .+hathi_upd_#{missingday_first_ymd}.txt.gz/)
        expect(verifier.errors).to include(/No listing with filename: hathi_full_#{missingday_first_ymd}.txt.gz .+/)
        expect(verifier.errors).to include(/not found: .+hathi_full_#{missingday_first_ymd}.txt.gz/)
      end

      it "produces 2 errors if upd file is missing midmonth + no listing" do
        verifier.verify_hathifiles_listing(date: missingday_second)
        expect(verifier.errors.count).to eq 2 # 1 file not found, 1 listing not found
        expect(verifier.errors).to include(/No listing with filename: hathi_upd_#{missingday_second_ymd}.txt.gz .+/)
        expect(verifier.errors).to include(/not found: .+hathi_upd_#{missingday_second_ymd}.txt.gz/)
      end
    end

    describe "#verify_file_in_json" do
      it "finds a matching listing" do
        verifier.verify_file_in_json(filename: "hathi_full_#{firstday_ymd}.txt.gz")
        verifier.verify_file_in_json(filename: "hathi_upd_#{firstday_ymd}.txt.gz")
        verifier.verify_file_in_json(filename: "hathi_upd_#{secondday_ymd}.txt.gz")
      end
      it "produces 1 error when not finding a matching listing" do
        verifier.verify_file_in_json(filename: "hathi_upd_#{missingday_first_ymd}.txt.gz")
        expect(verifier.errors.size).to eq 1
        expect(verifier.errors).to include(/No listing with filename: hathi_upd_#{missingday_first_ymd}.txt.gz .+/)
      end
    end
  end
end
