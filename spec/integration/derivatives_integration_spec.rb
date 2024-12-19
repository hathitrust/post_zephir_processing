# frozen_string_literal: true

require "date"
require "fileutils"
require "tmpdir"
require "derivative/catalog"
require "derivative/delete"
require "derivative/rights"

module PostZephirProcessing
  RSpec.describe Derivatives do
    def catalog_prep_dir
      File.join(@tmpdir, "catalog_prep")
    end

    def rights_dir
      File.join(@tmpdir, "rights")
    end

    def rights_archive_dir
      File.join(@tmpdir, "rights_archive")
    end

    # Set derivative env vars, and populate test dir with the appropriate
    # directories.
    def with_test_dirs(parent_dir:)
      ClimateControl.modify(
        CATALOG_PREP: catalog_prep_dir,
        RIGHTS_ARCHIVE: rights_archive_dir
      ) do
        [catalog_prep_dir, rights_archive_dir].each do |loc|
          Dir.mkdir loc
        end

        yield
      end
    end

    def full_rights_file_for_date(date:)
      Derivative::Rights.new(date: date, full: true).path
    end

    def update_rights_file_for_date(date:)
      Derivative::Rights.new(date: date, full: false).path
    end

    def full_file_for_date(date:)
      Derivative::CatalogPrep.new(date: date, full: true).path
    end

    def update_file_for_date(date:)
      Derivative::CatalogPrep.new(date: date, full: false).path
    end

    def delete_file_for_date(date:)
      Derivative::Delete.new(date: date).path
    end

    # @param date [Date] determines the month and year for the file datestamps
    def setup_test_files(date:)
      start_date = Date.new(date.year, date.month - 1, -1)
      `touch #{full_file_for_date(date: start_date)}`
      `touch #{full_rights_file_for_date(date: start_date)}`
      end_date = Date.new(date.year, date.month, -2)
      (start_date..end_date).each do |d|
        `touch #{update_file_for_date(date: d)}`
        `touch #{delete_file_for_date(date: d)}`
        `touch #{update_rights_file_for_date(date: d)}`
      end
    end

    around(:each) do |example|
      with_test_environment do |tmpdir|
        with_test_dirs(parent_dir: tmpdir) do
          example.run
        end
      end
    end

    it "with no files present, returns the last day of last month" do
      expect(described_class
        .new(date: Date.parse("2023-01-15"))
        .earliest_missing_date)
        .to eq Date.parse("2022-12-31")
    end

    context "with test files" do
      let(:date_for_run) { Date.parse("2023-11-29") }
      let(:verifier) { described_class.new(date: date_for_run) }

      before(:each) { setup_test_files(date: date_for_run) }

      it "with all files present, returns nil" do
        expect(verifier.earliest_missing_date).to be_nil
      end

      it "with one date missing, returns the earliest" do
        date = Date.parse("2023-11-03")
        FileUtils.rm update_rights_file_for_date(date: date)

        expect(verifier.earliest_missing_date).to eq date
      end

      it "with monthly file missing, returns the last day of the last month" do
        date = Date.parse("2023-10-31")
        FileUtils.rm full_file_for_date(date: date)
        expect(verifier.earliest_missing_date).to eq date
      end

      it "with different dates in each category missing, returns the earliest" do
        [
          delete_file_for_date(date: Date.parse("2023-11-20")),
          update_file_for_date(date: Date.parse("2023-11-11")),
          update_rights_file_for_date(date: Date.parse("2023-11-18"))
        ].each do |file|
          FileUtils.rm file
        end
        expect(verifier.earliest_missing_date).to eq Date.parse("2023-11-11")
      end

      it "with multiple dates missing, returns the earliest" do
        dates = (Date.parse("2023-11-24")..Date.parse("2023-11-29"))
        dates.each do |date|
          FileUtils.rm delete_file_for_date(date: date)
        end
        expect(verifier.earliest_missing_date).to eq dates.first
      end
    end
  end
end
