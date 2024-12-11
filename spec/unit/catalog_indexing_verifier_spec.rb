# frozen_string_literal: true

require "verifier/catalog_index_verifier"
require "webmock"

module PostZephirProcessing
  RSpec.describe(CatalogIndexVerifier) do
    let(:solr_url) { "http://solr-sdr-catalog:9033/solr/catalog" }

    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(SOLR_URL: solr_url) do
          example.run
        end
      end
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
      let(:verifier) { described_class.new }
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
          expect(verifier.errors).not_to be_empty
        end
        it "rejects a catalog with 2 recent updates" do
          stub_catalog_timerange(catalog_index_date, 2)
          verifier.verify_index_count(path: catalog_update)
          expect(verifier.errors).not_to be_empty
        end
      end

      context "with a catalog full file with 5 records" do
        it "accepts a catalog with 5 records"
        it "accepts a catalog with 6 records"
        it "rejects a catalog with no records"
        it "rejects a catalog with 2 records"
      end
    end
  end

  describe "#run" do
    it "checks the full file on the last day of the month"
    it "checks the file corresponding to today's date"
  end
end
