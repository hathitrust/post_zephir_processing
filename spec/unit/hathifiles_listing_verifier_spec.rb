# frozen_string_literal: true

require "verifier/hathifiles_listing_verifier"

module PostZephirProcessing
  RSpec.describe(HathifilesListingVerifier) do
    let(:verifier) { described_class.new }

    # Using secondday here as a representative for
    # "any day of the month that's not the 1st"
    # missingday does not have files or listings
    firstday = Date.parse("2023-01-01")
    secondday = Date.parse("2023-01-02")
    missingday = Date.parse("2023-01-13")
    firstday_ymd = firstday.strftime("%Y%m%d")
    secondday_ymd = secondday.strftime("%Y%m%d")
    missingday_ymd = missingday.strftime("%Y%m%d")
    dir_path = ENV["WWW_DIR"]

    before(:all) do
      FileUtils.cp(fixture("hathi_file_list.json"), dir_path)
    end

    around(:each) do |example|
      with_test_environment do
        example.run
      end
    end

    describe "#derivatives_for_date" do
      it "expects two derivativess on firstday" do
        expect(described_class.new.derivatives_for_date(date: firstday).size).to eq 2
      end

      it "expects one derivative on secondday" do
        expect(described_class.new.derivatives_for_date(date: secondday).size).to eq 1
      end
    end

    describe "#verify_hathifiles_listing" do
      FileUtils.mkdir_p(dir_path)

      it "finds update and full file on firstday" do
        update_file = File.join(dir_path, "hathi_upd_#{firstday_ymd}.txt.gz")
        full_file = File.join(dir_path, "hathi_full_#{firstday_ymd}.txt.gz")

        FileUtils.touch(update_file)
        FileUtils.touch(full_file)

        verifier.verify_hathifiles_listing(date: firstday)
        expect(verifier.errors).to be_empty
      end

      it "finds just an update file on secondday" do
        update_file = File.join(dir_path, "hathi_upd_#{secondday_ymd}.txt.gz")

        FileUtils.mkdir_p(dir_path)
        FileUtils.touch(update_file)

        verifier.verify_hathifiles_listing(date: secondday)
        expect(verifier.errors).to be_empty
      end

      it "produces 1 error if upd file is missing midmonth" do
        verifier.verify_hathifiles_listing(date: missingday)
        expect(verifier.errors.size).to eq 2
        expect(verifier.errors).to include(/Did not find a listing with filename: hathi_upd_#{missingday_ymd}/)
        expect(verifier.errors.first).to include(/not found:.+_upd_#{missingday_ymd}/)
      end

      it "produces 2 errors if upd and full file are missing on the first day of the month" do
        # Need to remove the 2 files for the first to test
        verifier.derivatives_for_date(date: firstday).each do |f|
          if File.exist?(f)
            FileUtils.rm(f)
          end
        end
        verifier.verify_hathifiles_listing(date: firstday)
        expect(verifier.errors.size).to eq 2
        expect(verifier.errors.first).to include(/not found:.+_upd_#{firstday_ymd}/)
        expect(verifier.errors.last).to include(/not found:.+_full_#{firstday_ymd}/)
      end
    end

    describe "#verify_file_in_json" do
      it "finds a matching listing" do
        verifier.verify_file_in_json(filename: "hathi_full_#{firstday_ymd}.txt.gz")
        verifier.verify_file_in_json(filename: "hathi_upd_#{firstday_ymd}.txt.gz")
        verifier.verify_file_in_json(filename: "hathi_upd_#{secondday_ymd}.txt.gz")
      end
      it "produces 1 error when not finding a matching listing" do
        verifier.verify_file_in_json(filename: "hathi_upd_#{missingday_ymd}.txt.gz")
        expect(verifier.errors.size).to eq 1
        expect(verifier.errors).to include(/Did not find a listing with filename: hathi_upd_#{missingday_ymd}/)
      end
    end
  end
end
