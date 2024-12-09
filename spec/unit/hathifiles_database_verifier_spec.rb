# frozen_string_literal: true

require "verifier/hathifiles_database_verifier"

module PostZephirProcessing
  TEST_UPDATE_FILE = fixture(File.join("hathifile_archive", "hathi_upd_20241202.txt.gz"))
  TEST_UPDATE_LINECOUNT = 8

  RSpec.describe(HathifilesDatabaseVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    # Temporarily add `hathifile` to `hf_log` with the current timestamp.
    def with_fake_hf_log_entry(hathifile:)
      Services[:database][:hf_log].where(hathifile: hathifile).delete
      Services[:database][:hf_log].insert(hathifile: hathifile)
      begin
        yield
      ensure
        Services[:database][:hf_log].where(hathifile: hathifile).delete
      end
    end

    # Temporarily add `htid` to `hf` with reasonable (and irrelevant) defaults.
    def with_fake_hf_entries(htids:)
      Services[:database][:hf].where(htid: htids).delete
      htids.each { |htid| Services[:database][:hf].insert(htid: htid) }
      begin
        yield
      ensure
        Services[:database][:hf].where(htid: htids).delete
      end
    end

    describe ".has_log?" do
      context "with corresponding hf_log" do
        it "returns `true`" do
          with_fake_hf_log_entry(hathifile: "hathi_upd_20241202.txt.gz") do
            expect(described_class.has_log?(hathifile: TEST_UPDATE_FILE)).to eq(true)
          end
        end
      end

      context "without corresponding hf_log" do
        it "returns `false`" do
          expect(described_class.has_log?(hathifile: TEST_UPDATE_FILE)).to eq(false)
        end
      end
    end

    describe ".db_count" do
      context "with no `hf` contents" do
        it "returns 0" do
          expect(described_class.db_count).to eq(0)
        end
      end

      context "without corresponding hf_log" do
        fake_htids = ["test.001", "test.002", "test.003", "test.004", "test.005"]
        it "returns the correct count > 0" do
          with_fake_hf_entries(htids: fake_htids) do
            expect(described_class.db_count.positive?).to eq(true)
            expect(described_class.db_count).to eq(fake_htids.count)
          end
        end
      end
    end

    describe ".gzip_linecount" do
      it "returns the correct number of lines" do
        expect(described_class.gzip_linecount(path: TEST_UPDATE_FILE)).to eq(TEST_UPDATE_LINECOUNT)
      end
    end
  end
end
