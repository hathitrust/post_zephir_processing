require_relative "../../bin/verify"

module PostZephirProcessing
  RSpec.describe "#run_verify" do
    include_context "with solr mocking"
    include_context "with hathifile database"

    around(:each) do |example|
      @test_log = StringIO.new
      old_logger = Services.logger
      Services.register(:logger) { Logger.new(@test_log, level: Logger::INFO) }
      example.run
      Services.register(:logger) { old_logger }
    end

    it "runs without error for date with fixtures" do
      ClimateControl.modify(
        HATHIFILE_ARCHIVE: fixture("hathifile_archive"),
        WWW_DIR: fixture("www"),
        CATALOG_ARCHIVE: fixture("catalog_archive"),
        RIGHTS_ARCHIVE: fixture("rights_archive"),
        REDIRECTS_DIR: fixture("redirects"),
        REDIRECTS_HISTORY_DIR: fixture("redirects"),
        CATALOG_PREP: fixture("catalog_prep"),
        TMPDIR: fixture("dollar_dup"),
        SOLR_URL: "http://solr-sdr-catalog:9033/solr/catalog",
        TZ: "America/Detroit"
      ) do
        stub_catalog_timerange("2024-12-03T05:00:00Z", 3)
        with_fake_hf_log_entry(hathifile: "hathi_upd_20241203.txt.gz") do
          PostZephirProcessing.run_verifiers(Date.parse("2024-12-03"))
        end
      end

      # TODO: dollar-dup, hf_log (database)

      %w[PostZephirVerifier
        PopulateRightsVerifier
        HathifilesVerifier
        HathifilesDatabaseVerifier
        HathifilesListingVerifier
        HathifileRedirectsVerifier
        CatalogIndexVerifier].each do |verifier|
        expect(@test_log.string).to include(/.*INFO.*#{verifier}/)
      end
      expect(@test_log.string).not_to include(/.*ERROR.*/)
    end
  end
end
