# frozen_string_literal: true

require "date"
require "fileutils"
require "tmpdir"

RSpec.describe "Derivatives Integration" do
  around(:each) do |example|
    Dir.mktmpdir do |tmpdir|
      setup_test_dirs(parent_dir: tmpdir)
      setup_test_files(date: Date.parse("2023-11-29"))
      example.run
    end
  end

  describe "all files present" do
    it "returns nil" do
      mi = PostZephirProcessing::Derivatives.new(date: Date.parse("2023-11-29"))
      expect(mi.earliest_missing_date).to be_nil
    end
  end

  describe "one date missing" do
    it "returns the earliest" do
      date = Date.parse("2023-11-03")
      FileUtils.rm update_rights_file_for_date(date: date)
      mi = PostZephirProcessing::Derivatives.new(date: Date.parse("2023-11-29"))
      expect(mi.earliest_missing_date).to eq date
    end
  end

  describe "monthly missing" do
    it "returns the last day of the last month" do
      date = Date.parse("2023-10-31")
      FileUtils.rm full_file_for_date(date: date)
      mi = PostZephirProcessing::Derivatives.new(date: Date.parse("2023-11-29"))
      expect(mi.earliest_missing_date).to eq date
    end
  end

  describe "different date in each category missing" do
    it "returns the earliest" do
      [
        delete_file_for_date(date: Date.parse("2023-11-20")),
        update_file_for_date(date: Date.parse("2023-11-11")),
        update_rights_file_for_date(date: Date.parse("2023-11-18"))
      ].each do |file|
        FileUtils.rm file
      end
      mi = PostZephirProcessing::Derivatives.new(date: Date.parse("2023-11-29"))
      expect(mi.earliest_missing_date).to eq Date.parse("2023-11-11")
    end
  end

  describe "multiple dates missing" do
    it "returns the earliest" do
      dates = (Date.parse("2023-11-24")..Date.parse("2023-11-29"))
      dates.each do |date|
        FileUtils.rm delete_file_for_date(date: date)
      end
      mi = PostZephirProcessing::Derivatives.new(date: Date.parse("2023-11-29"))
      expect(mi.earliest_missing_date).to eq dates.first
    end
  end
end
