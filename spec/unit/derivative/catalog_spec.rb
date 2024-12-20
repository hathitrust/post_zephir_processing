# frozen_string_literal: true

require "derivative"
require "derivative/catalog"

module PostZephirProcessing
  RSpec.describe(Derivative::Catalog) do
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

    let(:test_date_first_of_month) { Date.parse("2023-12-01") }
    let(:test_date_second_of_month) { Date.parse("2023-12-02") }

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

      it "returns 1 derivative after the first of month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_second_of_month
        )
        expect(derivatives.count).to eq 1
      end
    end

    describe(Derivative::CatalogArchive) do
      it "reports the expected path for a full catalog file" do
        params[:full] = true
        expect(derivative.path).to eq "/tmp/archive/zephir_full_20231130_vufind.json.gz"
      end

      it "reports the expected path for an update catalog file" do
        params[:full] = false
        expect(derivative.path).to eq "/tmp/archive/zephir_upd_20231130.json.gz"
      end
    end

    describe(Derivative::CatalogPrep) do
      it "reports the expected path for a full catalog file" do
        params[:full] = true
        expect(derivative.path).to eq "/tmp/prep/zephir_full_20231130_vufind.json.gz"
      end

      it "reports the expected path for an update catalog file" do
        params[:full] = false
        expect(derivative.path).to eq "/tmp/prep/zephir_upd_20231130.json.gz"
      end
    end
  end
end
