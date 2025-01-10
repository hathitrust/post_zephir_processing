# frozen_string_literal: true

require "verifier/hathifiles_database"

module PostZephirProcessing
  RSpec.describe(Verifier::HathifilesDatabase) do
    include_context "with hathifile database"

    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(HATHIFILE_ARCHIVE: fixture("hathifile_archive")) do
          example.run
        end
      end
    end

    let(:verifier) { described_class.new }
    let(:test_update_file) { "hathi_upd_20241202.txt.gz" }
    let(:test_update_fixture) { fixture(File.join("hathifile_archive", test_update_file)) }
    let(:test_full_file) { "hathi_full_20241101.txt.gz" }
    let(:test_full_fixture) { fixture(File.join("hathifile_archive", test_full_file)) }
    let(:first_of_month) { Date.parse("2024-11-01") }
    let(:second_of_month) { Date.parse("2024-12-02") }
    let(:fake_upd_htids) { (1..5).map { |n| "test.%03d" % n } }
    let(:fake_full_htids) { (1..11).map { |n| "test.%03d" % n } }

    describe ".has_log?" do
      context "with corresponding hf_log" do
        it "returns `true`" do
          with_fake_hf_log_entry(hathifile: "hathi_upd_20241202.txt.gz") do
            expect(described_class.has_log?(hathifile: test_update_fixture)).to be true
          end
        end
      end

      context "without corresponding hf_log" do
        it "returns `false`" do
          expect(described_class.has_log?(hathifile: test_update_fixture)).to be false
        end
      end
    end

    describe ".db_count" do
      context "with no `hf` contents" do
        it "returns 0" do
          expect(described_class.db_count).to eq 0
        end
      end

      context "with `hf` contents" do
        it "returns the correct count > 0" do
          with_fake_hf_entries(htids: fake_upd_htids) do
            expect(described_class.db_count.positive?).to be true
            expect(described_class.db_count).to eq(fake_upd_htids.count)
          end
        end
      end
    end

    describe "#run_for_date" do
      context "with upd hathifile" do
        context "with corresponding hf_log" do
          it "reports no `missing hf_log` errors" do
            with_fake_hf_log_entry(hathifile: "hathi_upd_20241202.txt.gz") do
              verifier.run_for_date(date: second_of_month)
              expect(verifier.errors).to be_empty
            end
          end
        end

        context "with no corresponding hf_log" do
          it "reports `missing hf_log` error" do
            verifier.run_for_date(date: second_of_month)
            expect(verifier.errors.count).to eq 1
          end
        end
      end

      context "with full hathifile" do
        context "with corresponding hf_log" do
          it "reports no errors" do
            with_fake_hf_log_entry(hathifile: test_full_file) do
              with_fake_hf_entries(htids: fake_full_htids) do
                verifier.run_for_date(date: first_of_month)
                expect(verifier.errors).to be_empty
              end
            end
          end
        end

        context "with no corresponding hf_log" do
          it "reports `missing hf_log` error" do
            with_fake_hf_entries(htids: fake_full_htids) do
              verifier.run_for_date(date: first_of_month)
              expect(verifier.errors.count).to eq 1
            end
          end
        end

        context "with the expected `hf` rows" do
          it "reports no `hf count mismatch` errors" do
            with_fake_hf_log_entry(hathifile: test_full_file) do
              with_fake_hf_entries(htids: fake_full_htids) do
                verifier.run_for_date(date: first_of_month)
                expect(verifier.errors).to be_empty
              end
            end
          end
        end

        context "without the expected `hf` rows" do
          it "reports one `hf count mismatch` error" do
            with_fake_hf_log_entry(hathifile: test_full_file) do
              verifier.run_for_date(date: first_of_month)
              expect(verifier.errors.count).to eq 1
            end
          end
        end
      end
    end
  end
end
