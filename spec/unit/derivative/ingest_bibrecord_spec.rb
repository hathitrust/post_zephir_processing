# frozen_string_literal: true

require "derivative"
require "derivative/ingest_bibrecord"

module PostZephirProcessing
  RSpec.describe(Derivative::IngestBibrecord) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          INGEST_BIBRECORDS: fixture("ingest_bibrecords")
        ) do
          example.run
        end
      end
    end

    let(:test_date_first_of_month) { Date.parse("2023-12-01") }

    describe "#{described_class}.derivatives_for_date" do
      it "returns 2 derivatives on the first of the month, otherwise 0" do
        2.upto(31) do |day|
          date = Date.new(2023, 12, day)
          expect(described_class.derivatives_for_date(date: date)).to be_empty
        end
        expect(described_class.derivatives_for_date(date: test_date_first_of_month).count).to eq 2
      end
      it "reports the expected paths" do
        derivative_paths = described_class.derivatives_for_date(date: test_date_first_of_month).map { |d| d.path }
        expect(derivative_paths).to include(fixture("ingest_bibrecords/groove_full.tsv.gz"))
        expect(derivative_paths).to include(fixture("ingest_bibrecords/zephir_ingested_items.txt.gz"))
      end
    end
  end
end
