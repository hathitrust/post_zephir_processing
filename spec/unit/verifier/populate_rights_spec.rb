# frozen_string_literal: true

require "verifier/populate_rights"
require "derivative/rights"
require "pry"

module PostZephirProcessing
  RSpec.describe(Verifier::PopulateRights) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(RIGHTS_ARCHIVE: @tmpdir) do
          Services[:database][:rights_current].truncate
          example.run
          Services[:database][:rights_current].truncate
        end
      end
    end

    let(:test_rights) { (0..9).map { |n| "test.%03d" % n } }
    let(:test_rights_file_contents) do
      test_rights.map do |rights|
        [rights, "ic", "bib", "bibrights", "aa"].join("\t")
      end.join("\n")
    end
    # Choose a small slice size to make sure we have leftovers after the main rights fetch loop.
    let(:verifier) { described_class.new(slice_size: 3) }
    let(:db) { Services[:database][:rights_current] }

    # Creates a full or upd rights file in @tmpdir.
    def with_fake_rights_file(date:, full: false)
      rights_file = Derivative::Rights.derivatives_for_date(date: date)
        .find { |derivative| derivative.full? == full }
        .path
      File.write(rights_file, test_rights_file_contents)
      yield
    end

    def insert_fake_rights(namespace:, id:)
      db.insert(namespace: namespace, id: id, attr: 1, reason: 1, source: 1, access_profile: 1)
    end

    # Temporarily add each `htid` to `rights_current` with resonable (and irrelevant) default values.

    context "with HTIDs in the rights database" do
      around(:each) do |example|
        split_htids = test_rights.map { |htid| htid.split(".", 2) }
        split_htids.each do |split_htid|
          insert_fake_rights(namespace: split_htid[0], id: split_htid[1])
        end
        example.run
      end

      describe "#run_for_date" do
        it "logs no `missing rights_current` error for full file" do
          run_date = Date.parse("2024-12-01")
          with_fake_rights_file(date: run_date, full: true) do
            verifier.run_for_date(date: run_date)
            # The only error is for the missing upd file.
            expect(verifier.errors.count).to eq 1
            missing_rights_errors = verifier.errors.select { |err| /missing rights_current/.match? err }
            expect(missing_rights_errors).to be_empty
          end
        end

        it "logs no `missing rights_current` error for update file" do
          date = Date.parse("2024-12-02")
          with_fake_rights_file(date: date) do
            verifier.run_for_date(date: date)
            expect(verifier.errors).to be_empty
          end
        end
      end

      describe "#verify_rights_file" do
        it "logs no error" do
          expect_ok(:verify_rights_file, test_rights_file_contents)
        end
      end
    end

    context "with no HTIDs in the rights database" do
      describe "#run_for_date" do
        it "logs `missing rights_current` error for full file" do
          run_date = Date.parse("2024-12-01")
          with_fake_rights_file(date: run_date, full: true) do
            verifier.run_for_date(date: run_date)
            # There will be an error for the missing upd file, ignore it.
            missing_rights_errors = verifier.errors.select { |err| /missing rights_current/.match? err }
            expect(missing_rights_errors.count).to eq test_rights.count
          end
        end

        it "logs an error for each HTID in the update file" do
          date = Date.parse("2024-12-02")
          with_fake_rights_file(date: date) do
            verifier.run_for_date(date: date)
            expect(verifier.errors.count).to eq test_rights.count
          end
        end
      end

      describe "#verify_rights_file" do
        it "logs `missing rights_current` error" do
          expect_not_ok(:verify_rights_file, test_rights_file_contents, errmsg: /missing rights_current/)
        end
      end
    end
  end
end
