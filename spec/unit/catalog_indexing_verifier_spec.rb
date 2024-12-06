# frozen_string_literal: true

require "verifier/catalog_index_verifier"

module PostZephirProcessing
  RSpec.describe(CatalogIndexVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    def stub_catalog_timerange(date, result_count)
      # must be like YYYY-mm-ddTHH:MM:SSZ - iso8601 with a 'Z' for time zone -
      # time zone offsets like DateTime.iso8601 produce by default are't
      # allowed for solr
      datebegin = date.to_datetime.new_offset(0).strftime("%FT%TZ")
      dateend = (date + 1).to_datetime.new_offset(0).strftime("%FT%TZ")
      WebMock.enable!

      url = "http://solr-sdr-catalog:9033/solr/catalog/select?fq=time_of_index:#{datebegin}%20TO%20#{dateend}]&indent=on&q=*:*&rows=0&wt=json"

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
        .with(body: result, headers: {"Content-Type" => "application/json"})
    end

    describe "#verify_index_count" do
      let(:verifier) { described_class.new }
      context "with a catalog update file with 3 records" do
        it "accepts a catalog with 3 recent updates"
        it "accepts a catalog with 5 recent updates"
        it "rejects a catalog with no recent updates"
        it "rejects a catalog with 2 recent updates"
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
