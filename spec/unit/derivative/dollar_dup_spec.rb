# frozen_string_literal: true

require "derivative"
require "derivative/dollar_dup"

module PostZephirProcessing
  RSpec.describe(Derivative::DollarDup) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          TMPDIR: "/tmp"
        ) do
          example.run
        end
      end
    end

    let(:test_date_first_of_month) { Date.parse("2023-11-01") }
    let(:test_date_last_of_month) { Date.parse("2023-11-30") }

    let(:params) do
      {
        date: test_date_last_of_month,
        full: false
      }
    end
    let(:derivative) { described_class.new(**params) }

    describe "self.derivatives_for_date" do
      it "returns 1 derivative (upd) on the last of month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_last_of_month
        )
        expect(derivatives.count).to eq 1
        expect(derivatives.first.full?).to be false
      end

      it "returns 1 derivative (upd) on the first of month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_first_of_month
        )
        expect(derivatives.count).to eq 1
        expect(derivatives.first.full?).to be false
      end
    end

    it "reports the expected path for a dollar dup file" do
      expect(derivative.path).to eq "/tmp/vufind_incremental_2023-11-30_dollar_dup.txt.gz"
    end

    it "raises if a full file is requested" do
      params[:full] = true
      expect { derivative }.to raise_exception(ArgumentError, /full/)
    end
  end
end
