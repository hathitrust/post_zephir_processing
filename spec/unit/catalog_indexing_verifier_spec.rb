# frozen_string_literal: true

require "verifier/catalog_index_verifier"
require "webmock"

module PostZephirProcessing
  RSpec.describe(CatalogIndexVerifier) do
    let(:solr_url) { "http://solr-sdr-catalog:9033/solr/catalog" }
    let(:verifier) { described_class.new }

    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(SOLR_URL: solr_url) do
          example.run
        end
      end
    end

    def stub_catalog_record_count(result_count)
      WebMock.enable!

      url = "#{solr_url}/select?fq=deleted:false&q=*:*&rows=0&wt=json"

      result = {
        "responseHeader" => {
          "status" => 0,
          "QTime" => 0,
          "params" => {
            "q" => "*=>*",
            "fq" => "deleted:false",
            "rows" => "0",
            "wt" => "json"
          }
        },
        "response" => {"numFound" => result_count, "start" => 0, "docs" => []}
      }.to_json

      WebMock::API.stub_request(:get, url)
        .to_return(body: result, headers: {"Content-Type" => "application/json"})
    end

    def stub_catalog_timerange(date, result_count)
      # must be like YYYY-mm-ddTHH:MM:SSZ - iso8601 with a 'Z' for time zone -
      # time zone offsets like DateTime.iso8601 produce by default are't
      # allowed for solr

      # FIXME: don't love that we duplicate this logic & the URL between here &
      # the verifier -- anything to do?
      datebegin = date.to_datetime.new_offset(0).strftime("%FT%TZ")
      dateend = (date + 1).to_datetime.new_offset(0).strftime("%FT%TZ")
      WebMock.enable!

      url = "#{solr_url}/select?fq=time_of_index:#{datebegin}%20TO%20#{dateend}]&q=*:*&rows=0&wt=json"

      result = {
        "responseHeader" => {
          "status" => 0,
          "QTime" => 0,
          "params" => {
            "q" => "*=>*",
            "fq" => "time_of_index:[#{datebegin} TO #{dateend}]",
            "rows" => "0",
            "wt" => "json"
          }
        },
        "response" => {"numFound" => result_count, "start" => 0, "docs" => []}
      }.to_json

      WebMock::API.stub_request(:get, url)
        .to_return(body: result, headers: {"Content-Type" => "application/json"})
    end

    describe "#verify_index_count" do
      context "with a catalog update file with 3 records" do
        let(:catalog_update) { fixture("catalog_archive/zephir_upd_20241202.json.gz") }
        # indexed the day after the date in the filename
        let(:catalog_index_date) { Date.parse("2024-12-03") }

        it "accepts a catalog with 3 recent updates" do
          stub_catalog_timerange(catalog_index_date, 3)
          verifier.verify_index_count(path: catalog_update)
          expect(verifier.errors).to be_empty
        end
        it "accepts a catalog with 5 recent updates" do
          stub_catalog_timerange(catalog_index_date, 5)
          verifier.verify_index_count(path: catalog_update)
          expect(verifier.errors).to be_empty
        end
        it "rejects a catalog with no recent updates" do
          stub_catalog_timerange(catalog_index_date, 0)
          verifier.verify_index_count(path: catalog_update)
          expect(verifier.errors).to include(/only 0 .* in solr/)
        end
        it "rejects a catalog with 2 recent updates" do
          stub_catalog_timerange(catalog_index_date, 2)
          verifier.verify_index_count(path: catalog_update)
          expect(verifier.errors).to include(/only 2 .* in solr/)
        end
      end

      context "with a catalog full file with 5 records" do
        let(:catalog_full) { fixture("catalog_archive/zephir_full_20241130_vufind.json.gz") }

        it "accepts a catalog with 5 records" do
          stub_catalog_record_count(5)
          verifier.verify_index_count(path: catalog_full)
          expect(verifier.errors).to be_empty
        end
        it "accepts a catalog with 6 records" do
          stub_catalog_record_count(6)
          verifier.verify_index_count(path: catalog_full)
          expect(verifier.errors).to be_empty
        end
        it "rejects a catalog with no records" do
          stub_catalog_record_count(0)
          verifier.verify_index_count(path: catalog_full)
          expect(verifier.errors).to include(/only 0 .* in solr/)
        end
        it "rejects a catalog with 2 records" do
          stub_catalog_record_count(2)
          verifier.verify_index_count(path: catalog_full)
          expect(verifier.errors).to include(/only 2 .* in solr/)
        end
      end

      it "raises an exception when given some other file" do
        expect { verifier.verify_index_count(path: fixture("zephir_data/ht_bib_export_full_2024-11-30.json.gz")) }.to raise_exception(ArgumentError)
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
