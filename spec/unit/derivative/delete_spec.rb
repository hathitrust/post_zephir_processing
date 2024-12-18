# frozen_string_literal: true

require "derivative"
require "derivative/delete"

module PostZephirProcessing
  RSpec.describe(Derivative::Delete) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          CATALOG_ARCHIVE: "/tmp/archive",
          CATALOG_PREP: "/tmp/prep"
        ) do
          example.run
        end
      end
    end

    let(:test_date_first_of_month) { Date.parse("2023-11-01") }
    let(:test_date_last_of_month) { Date.parse("2023-11-30") }

    let(:params) do
      {
        date: test_date_last_of_month
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
    
    it "reports the expected path for a delete file derived from an update catalog file" do
      params[:full] = false
      expect(derivative.path).to eq "/tmp/prep/zephir_upd_20231130_delete.txt.gz"
    end

    # TODO: maybe this should raise since it's asking for a nonexistent derivative?
    it "reports the same (upd) path regardless of fullness" do
      params[:full] = true
      expect(derivative.path).to eq "/tmp/prep/zephir_upd_20231130_delete.txt.gz"
    end
  end
end
