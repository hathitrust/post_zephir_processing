# frozen_string_literal: true

require "verifier/hathifiles_database_verifier"

module PostZephirProcessing
  TEST_UPDATE_FILE = "hathi_upd_20241202.txt.gz"
  TEST_UPDATE_FIXTURE = fixture(File.join("hathifile_archive", TEST_UPDATE_FILE))
  TEST_FULL_FILE = "hathi_full_20241201.txt.gz"
  TEST_UPDATE_LINECOUNT = 8

  RSpec.describe(HathifilesDatabaseVerifier) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(HATHIFILE_ARCHIVE: fixture("hathifile_archive")) do
          example.run
        end
      end
    end

    let(:verifier) { described_class.new }

    def delete_hf_logs
      Services[:database][:hf_log].delete
    end

    # Temporarily add `hathifile` to `hf_log` with the current timestamp.
    def with_fake_hf_log_entry(hathifile:)
      delete_hf_logs
      Services[:database][:hf_log].insert(hathifile: hathifile)
      begin
        yield
      ensure
        delete_hf_logs
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

    # Copies one of our fixtures into @tmpdir and renames it.
    # Could just use an additional fixture if we're not worried about the proliferation
    # of them.
    def with_fake_full_hathifile
      ClimateControl.modify(HATHIFILE_ARCHIVE: @tmpdir) do
        FileUtils.cp(TEST_UPDATE_FIXTURE, File.join(@tmpdir, TEST_FULL_FILE))
        yield
      end
    end

    describe ".has_log?" do
      context "with corresponding hf_log" do
        it "returns `true`" do
          with_fake_hf_log_entry(hathifile: "hathi_upd_20241202.txt.gz") do
            expect(described_class.has_log?(hathifile: TEST_UPDATE_FIXTURE)).to eq(true)
          end
        end
      end

      context "without corresponding hf_log" do
        it "returns `false`" do
          expect(described_class.has_log?(hathifile: TEST_UPDATE_FIXTURE)).to eq(false)
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

    describe "#run_for_date" do
      context "with upd hathifile" do
        context "with corresponding hf_log" do
          it "reports no `missing hf_log` errors" do
            with_fake_hf_log_entry(hathifile: "hathi_upd_20241202.txt.gz") do
              verifier.run_for_date(date: Date.new(2024, 12, 2))
              expect(verifier.errors).not_to include(/missing hf_log/)
            end
          end
        end

        context "with no corresponding hf_log" do
          it "reports `missing hf_log` error" do
            verifier.run_for_date(date: Date.new(2024, 12, 2))
            expect(verifier.errors).to include(/missing hf_log/)
          end
        end
      end

      # Each of these must be run with `with_fake_full_hathifile`
      context "with full hathifile" do
        context "with corresponding hf_log" do
          it "reports no `missing hf_log` errors" do
            with_fake_hf_log_entry(hathifile: TEST_FULL_FILE) do
              with_fake_full_hathifile do
                verifier.run_for_date(date: Date.new(2024, 12, 1))
                expect(verifier.errors).not_to include(/missing hf_log/)
              end
            end
          end
        end

        context "with no corresponding hf_log" do
          it "reports `missing hf_log` error" do
            with_fake_full_hathifile do
              verifier.run_for_date(date: Date.new(2024, 12, 1))
              expect(verifier.errors).to include(/missing hf_log/)
            end
          end
        end

        context "with the expected `hf` rows" do
          it "reports no `hf count mismatch` errors" do
            with_fake_hf_log_entry(hathifile: TEST_FULL_FILE) do
              with_fake_full_hathifile do
                fake_htids = ["test.001", "test.002", "test.003", "test.004", "test.005", "test.006", "test.007", "test.008"]
                with_fake_hf_entries(htids: fake_htids) do
                  verifier.run_for_date(date: Date.new(2024, 12, 1))
                  expect(verifier.errors).not_to include(/hf count mismatch/)
                end
              end
            end
          end
        end

        context "without the expected `hf` rows" do
          it "reports `hf count mismatch` error" do
            with_fake_hf_log_entry(hathifile: TEST_FULL_FILE) do
              with_fake_full_hathifile do
                verifier.run_for_date(date: Date.new(2024, 12, 1))
                expect(verifier.errors).to include(/hf count mismatch/)
              end
            end
          end
        end
      end
    end
  end
end
