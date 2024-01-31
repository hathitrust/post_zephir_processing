# frozen_string_literal: true

require "date"
require "fileutils"
require "tmpdir"

RSpec.describe "MonthlyInventory Integration" do
  around(:each) do |example|
    Dir.mktmpdir do |tmpdir|
      setup_test_dirs(parent_dir: tmpdir)
      setup_test_files(date: Date.parse("2023-11-01"))
      example.run
    end
  end

  describe "all files present" do
    it "returns nil" do
      mi = PostZephirProcessing::MonthlyInventory.new(date: Date.parse("2023-11-30"))
      expect(mi.earliest_missing_date).to be_nil
    end
  end

  describe "one date missing" do
    it "returns the earliest" do
      date = Date.parse("2023-11-03")
      FileUtils.rm rights_file_for_date(date: date)
      mi = PostZephirProcessing::MonthlyInventory.new(date: Date.parse("2023-11-30"))
      expect(mi.earliest_missing_date).to eq date
    end
  end

  describe "different date in each category missing" do
    it "returns the earliest" do
      [
        delete_file_for_date(date: Date.parse("2023-11-20")),
        update_file_for_date(date: Date.parse("2023-11-19")),
        rights_file_for_date(date: Date.parse("2023-11-18")),
        groove_file_for_date(date: Date.parse("2023-11-17")),
        touched_file_for_date(date: Date.parse("2023-11-16"))
      ].each do |file|
        FileUtils.rm file
      end
      mi = PostZephirProcessing::MonthlyInventory.new(date: Date.parse("2023-11-30"))
      expect(mi.earliest_missing_date).to eq Date.parse("2023-11-16")
    end
  end

  describe "multiple dates missing" do
    it "returns the earliest" do
      dates = (Date.parse("2023-11-26")..Date.parse("2023-11-30"))
      dates.each do |date|
        FileUtils.rm delete_file_for_date(date: date)
      end
      mi = PostZephirProcessing::MonthlyInventory.new(date: Date.parse("2023-11-30"))
      expect(mi.earliest_missing_date).to eq dates.first
    end
  end

  describe "find file not yet moved to archive directory" do
    it "returns nil" do
      date = Date.parse("2023-11-10")
      FileUtils.mv groove_file_for_date(date: date), groove_file_for_date(date: date, archive: false)
      mi = PostZephirProcessing::MonthlyInventory.new(date: Date.parse("2023-11-30"))
      expect(mi.earliest_missing_date).to be_nil
    end
  end
end
