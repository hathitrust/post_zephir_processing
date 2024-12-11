# frozen_string_literal: true

require "verifier/populate_rights_verifier"

module PostZephirProcessing
  RSpec.describe(PopulateRightsVerifier) do
    around(:each) do |example|
      with_test_environment do
        ClimateControl.modify(RIGHTS_ARCHIVE: @tmpdir) do
          example.run
        end
      end
    end

    let(:test_rights) { 10.times.collect { |n| "test.%03d" % n } }
    let(:test_rights_file_contents) do
      test_rights.map do |rights|
        [rights, "ic", "bib", "bibrights", "aa"].join("\t")
      end.join("\n")
    end
    let(:verifier) { described_class.new }
    let(:db) { Services[:database][:rights_current] }

    # Creates a full or upd rights file in @tmpdir.
    def with_fake_rights_file(date:, full: false)
      rights_file = File.join(@tmpdir, full ? described_class::FULL_RIGHTS_TEMPLATE : described_class::UPD_RIGHTS_TEMPLATE)
        .sub(/YYYYMMDD/i, date.strftime("%Y%m%d"))
      File.write(rights_file, test_rights_file_contents)
      yield
    end

    def insert_fake_rights(namespace:, id:)
      db.insert(namespace: namespace, id: id, attr: 1, reason: 1, source: 1, access_profile: 1)
    end

    # Temporarily add each `htid` to `rights_current` with resonable (and irrelevant) default values.
    def with_fake_rights_entries(htids: test_rights)
      split_htids = htids.map { |htid| htid.split(".", 2) }
      Services[:database][:rights_current].where([:namespace, :id] => split_htids).delete
      split_htids.each do |split_htid|
        insert_fake_rights(namespace: split_htid[0], id: split_htid[1])
      end
      begin
        yield
      ensure
        Services[:database][:rights_current].where([:namespace, :id] => split_htids).delete
      end
    end

    describe "#run_for_date" do
      context "monthly" do
        date = Date.new(2024, 11, 30)
        context "with HTID in the Rights Database" do
          it "logs no `missing rights_current` error" do
            with_fake_rights_entries do
              with_fake_rights_file(date: date, full: true) do
                verifier.run_for_date(date: date)
                expect(verifier.errors).not_to include(/missing rights_current/)
              end
            end
          end
        end

        context "with HTID not in the Rights Database" do
          it "logs `missing rights_current` error" do
            with_fake_rights_file(date: date, full: true) do
              verifier.run_for_date(date: date)
              expect(verifier.errors).to include(/missing rights_current/)
            end
          end
        end
      end

      context "daily" do
        date = Date.new(2024, 12, 2)
        context "with HTID in the Rights Database" do
          it "logs no `missing rights_current` error" do
            with_fake_rights_entries do
              with_fake_rights_file(date: date) do
                verifier.run_for_date(date: date)
                expect(verifier.errors).not_to include(/missing rights_current/)
              end
            end
          end
        end

        context "with HTID not in the Rights Database" do
          it "logs `missing rights_current` error" do
            with_fake_rights_file(date: date) do
              verifier.run_for_date(date: date)
              expect(verifier.errors).to include(/missing rights_current/)
            end
          end
        end
      end
    end

    describe "#verify_rights_file" do
      context "with HTID in the Rights Database" do
        it "logs no error" do
          with_fake_rights_entries do
            expect_ok(:verify_rights_file, test_rights_file_contents)
          end
        end
      end

      context "with HTID not in the Rights Database" do
        it "logs `missing rights_current` error" do
          expect_not_ok(:verify_rights_file, test_rights_file_contents, errmsg: /missing rights_current/)
        end
      end
    end
  end
end
