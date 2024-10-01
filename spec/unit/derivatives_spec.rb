# frozen_string_literal: true

require "tmpdir"

module PostZephirProcessing
  RSpec.describe(Derivatives) do
    around(:each) do |example|
      Dir.mktmpdir do |tmpdir|
        setup_test_dirs(parent_dir: tmpdir)
        setup_test_files(date: Date.parse("2023-10-30"))
        example.run
      end
    end

    describe ".new" do
      it "creates a MonthlyInventory" do
        expect(described_class.new).to be_an_instance_of(Derivatives)
      end

      it "has a default date of yesterday" do
        expect(described_class.new.dates.date).to eq(Date.today - 1)
      end
    end

    describe "#dates" do
      it "returns a Dates object" do
        expect(described_class.new.dates).to be_an_instance_of(Dates)
      end
    end

    describe "#earliest_missing_date" do
      context "with no files" do
        it "returns the last day of last month" do
          expect(described_class.new(date: Date.parse("2023-01-15")).earliest_missing_date).to eq Date.parse("2022-12-31")
        end
      end

      context "with all files for the month present" do
        date = Date.parse("2023-10-15")
        it "returns nil" do
          expect(described_class.new(date: date).earliest_missing_date).to eq nil
        end
      end
    end
  end
end
