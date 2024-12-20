# frozen_string_literal: true

require "verifier/catalog_index_verifier"
require "webmock"
require "derivative/catalog"
require "uri"

module PostZephirProcessing
  RSpec.describe(CatalogIndexVerifier) do
    include_context "with solr mocking"
    let(:verifier) { described_class.new }

    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(
          SOLR_URL: solr_url,
          CATALOG_ARCHIVE: fixture("catalog_archive"),
          TZ: "America/Detroit"
        ) do
          example.run
        end
      end
    end

    describe "#verify_index_count" do
      context "with a catalog update file with 3 records" do
        let(:catalog_update) { Derivative::CatalogArchive.new(date: Date.parse("2024-12-02"), full: false) }
        # indexed the day after the date in the filename starting at midnight
        # EST
        let(:catalog_index_begin) { "2024-12-02T05:00:00Z" }

        it "accepts a catalog with 3 recent updates" do
          stub_catalog_timerange(catalog_index_begin, 3)
          verifier.verify_index_count(derivative: catalog_update)
          expect(verifier.errors).to be_empty
        end
        it "accepts a catalog with 5 recent updates" do
          stub_catalog_timerange(catalog_index_begin, 5)
          verifier.verify_index_count(derivative: catalog_update)
          expect(verifier.errors).to be_empty
        end
        it "rejects a catalog with no recent updates" do
          stub_catalog_timerange(catalog_index_begin, 0)
          verifier.verify_index_count(derivative: catalog_update)
          expect(verifier.errors).to include(/only 0 .* in solr/)
        end
        it "rejects a catalog with 2 recent updates" do
          stub_catalog_timerange(catalog_index_begin, 2)
          verifier.verify_index_count(derivative: catalog_update)
          expect(verifier.errors).to include(/only 2 .* in solr/)
        end
      end

      context "with a catalog full file with 5 records" do
        let(:catalog_full) { Derivative::CatalogArchive.new(date: Date.parse("2024-12-01"), full: true) }

        it "accepts a catalog with 5 records" do
          stub_catalog_record_count(5)
          verifier.verify_index_count(derivative: catalog_full)
          expect(verifier.errors).to be_empty
        end
        it "accepts a catalog with 6 records" do
          stub_catalog_record_count(6)
          verifier.verify_index_count(derivative: catalog_full)
          expect(verifier.errors).to be_empty
        end
        it "rejects a catalog with no records" do
          stub_catalog_record_count(0)
          verifier.verify_index_count(derivative: catalog_full)
          expect(verifier.errors).to include(/only 0 .* in solr/)
        end
        it "rejects a catalog with 2 records" do
          stub_catalog_record_count(2)
          verifier.verify_index_count(derivative: catalog_full)
          expect(verifier.errors).to include(/only 2 .* in solr/)
        end
      end
    end

    describe "#run_for_date" do
      it "checks the full file on the first day of the month" do
        verifier.run_for_date(date: Date.parse("2024-03-01"))
        expect(verifier.errors).to include(/.*not found.*zephir_full_20240229_vufind.json.gz.*/)
      end
      it "checks the update file corresponding to today's date" do
        verifier.run_for_date(date: Date.parse("2024-03-02"))
        expect(verifier.errors).to include(/.*not found.*zephir_upd_20240301.json.gz.*/)
      end
    end
  end
end
