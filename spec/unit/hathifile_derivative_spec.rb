# frozen_string_literal: true

require "derivative"
require "derivative/hathifile_derivative"

module PostZephirProcessing
  RSpec.describe(HathifileDerivative) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(HATHIFILE_ARCHIVE: "/tmp") do
          example.run
        end
      end
    end

    let(:test_date_first_of_month) { Date.parse("2023-11-01") }
    let(:test_date_last_of_month) { Date.parse("2023-11-30") }

    let(:params) do
      {
        date: test_date_first_of_month
      }
    end
    let(:derivative) { described_class.new(**params) }

    describe "self.derivatives_for_date" do
      it "returns 2 derivatives (one full, one upd) on the first of month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_first_of_month
        )
        expect(derivatives.count).to eq 2
        expect(derivatives.count { |d| d.full == true }).to eq 1
        expect(derivatives.count { |d| d.full == false }).to eq 1
      end

      it "returns 1 derivative on the last of month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_last_of_month
        )
        expect(derivatives.count).to eq 1
      end
    end

    it "reports the expected file name for a full hathifile" do
      params[:full] = true
      expect(derivative.path).to eq "/tmp/hathi_full_20231101.txt.gz"
    end

    it "reports the expected file name for a upd hathifile" do
      params[:full] = false
      expect(derivative.path).to eq "/tmp/hathi_upd_20231101.txt.gz"
    end
  end
end
