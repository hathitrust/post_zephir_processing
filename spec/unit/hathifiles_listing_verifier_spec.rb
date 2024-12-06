# frozen_string_literal: true

require "climate_control"
require "zlib"
require "verifier/hathifiles_listing_verifier"
require "tempfile"
require "logger"

module PostZephirProcessing
  RSpec.describe(HathifilesListingVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    # Using midmonth here as a stand-in for "any day of the month that's not the 1st"
    firstday = Date.parse("2023-01-01")
    midmonth = Date.parse("2023-01-15")
    firstday_ymd = firstday.strftime("%Y%m%d")
    midmonth_ymd = midmonth.strftime("%Y%m%d")

    describe "#derivatives_for_date" do
      it "expects one derivative midmonth" do
        expect(described_class.new.derivatives_for_date(date: midmonth).size).to eq 1
      end

      it "expects two derivativess on the first of the month" do
        expect(described_class.new.derivatives_for_date(date: firstday).size).to eq 2
      end
    end

    describe "#verify_hathifiles_listing" do
      dir_path = ENV["WWW_DIR"]
      FileUtils.mkdir_p(dir_path)

      it "finds an update file midmonth" do
        update_file = File.join(dir_path, "hathi_upd_#{midmonth_ymd}.txt.gz")

        FileUtils.mkdir_p(dir_path)
        FileUtils.touch(update_file)

        verifier = described_class.new
        verifier.verify_hathifiles_listing(date: midmonth)
        expect(verifier.errors).to be_empty
      end

      it "finds both update and full file on the first day of the month" do
        update_file = File.join(dir_path, "hathi_upd_#{firstday_ymd}.txt.gz")
        full_file = File.join(dir_path, "hathi_full_#{firstday_ymd}.txt.gz")

        FileUtils.touch(update_file)
        FileUtils.touch(full_file)

        verifier = described_class.new
        verifier.verify_hathifiles_listing(date: firstday)
        expect(verifier.errors).to be_empty
      end

      it "produces one error if upd file is missing mid month" do
        # Make sure file does not exist
        update_file = File.join(dir_path, "hathi_upd_#{midmonth_ymd}.txt.gz")
        if File.exist?(update_file)
          FileUtils.rm(update_file)
        end

        verifier = described_class.new
        verifier.verify_hathifiles_listing(date: midmonth)
        expect(verifier.errors.size).to eq 1
      end

      it "produces two errors if upd and full file are missing on the first day of the month" do
        # Make sure files do not exist
        update_file = File.join(dir_path, "hathi_upd_#{firstday_ymd}.txt.gz")
        full_file = File.join(dir_path, "hathi_full_#{firstday_ymd}.txt.gz")

        [update_file, full_file].each do |f|
          if File.exist?(f)
            FileUtils.rm(f)
          end
        end

        verifier = described_class.new
        verifier.verify_hathifiles_listing(date: firstday)
        expect(verifier.errors.size).to eq 2
      end
    end
  end
end
