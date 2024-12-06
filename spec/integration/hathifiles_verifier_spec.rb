# frozen_string_literal: true

require "climate_control"
require "verifier/hathifiles_verifier"

module PostZephirProcessing
  RSpec.describe HathifilesVerifier do
    let(:verifier) { described_class.new }

    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          HATHIFILE_ARCHIVE: fixture("hathifile_archive"),
          CATALOG_ARCHIVE: fixture("catalog_archive")
        ) do
          example.run
        end
      end
    end

    it "accepts a well-formed file with more entries than the corresponding catalog file" do
      verifier.run_for_date(date: Date.parse("2024-12-02"))
      expect(verifier.errors).to be_empty
    end

    it "rejects a file with fewer records than the corresponding catalog, some of which are malformed" do
      verifier.run_for_date(date: Date.parse("2024-12-03"))
      expect(verifier.errors).not_to be_empty
    end

    it "checks both the update and full file on the first of the month" do
      verifier.run_for_date(date: Date.parse("2024-12-01"))
      expect(verifier.errors).to include(/.*not found.*hathi_full_20241201.txt.gz.*/)
      expect(verifier.errors).to include(/.*not found.*hathi_upd_20241201.txt.gz.*/)
    end
  end
end
