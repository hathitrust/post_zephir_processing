# frozen_string_literal: true

require "derivative"
require "derivative/rights"

module PostZephirProcessing
  RSpec.describe(Derivative::Rights) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          RIGHTS_ARCHIVE: "/tmp/rights"
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
      it "returns 2 derivatives (one full, one upd) on the first of the month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_first_of_month
        )
        expect(derivatives.count).to eq 2
        expect(derivatives.count { |d| d.full == true }).to eq 1
        expect(derivatives.count { |d| d.full == false }).to eq 1
      end

      it "returns 1 derivative on the second of month" do
        derivatives = described_class.derivatives_for_date(
          date: test_date_second_of_month
        )
        expect(derivatives.count).to eq 1
      end

      it "reports the expected path for a rights file derived from a full catalog file" do
        params[:full] = true
        expect(derivative.path).to eq "/tmp/rights/zephir_full_20231130.rights"
      end

      it "reports the expected path for a rights file derived from an update catalog file" do
        params[:full] = false
        expect(derivative.path).to eq "/tmp/rights/zephir_upd_20231130.rights"
      end
    end
  end
end
