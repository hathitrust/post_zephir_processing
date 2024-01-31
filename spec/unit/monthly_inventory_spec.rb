# frozen_string_literal: true

require "tmpdir"

module PostZephirProcessing
  RSpec.describe(MonthlyInventory) do
    around(:each) do |example|
      Dir.mktmpdir do |tmpdir|
        setup_test_dirs(parent_dir: tmpdir)
        setup_test_files(date: Date.parse("2023-10-01"))
        example.run
      end
    end

    describe ".new" do
      it "creates a MonthlyInventory" do
        expect(described_class.new).to be_an_instance_of(MonthlyInventory)
      end

      it "has a default date of yesterday" do
        expect(described_class.new.date).to eq(Date.today - 1)
      end

      it "has a logger" do
        expect(described_class.new.logger).to be_an_instance_of(Logger)
      end

      it "has an inventory" do
        expect(described_class.new.inventory).to be_an_instance_of(Hash)
      end
    end

    describe "#date" do
      it "returns a Date" do
        expect(described_class.new.date).to be_an_instance_of(Date)
      end
    end

    describe "#earliest_missing_date" do
      context "with no files" do
        it "returns the first day of the month" do
          expect(described_class.new(date: Date.parse("2023-01-15")).earliest_missing_date).to eq Date.parse("2023-01-01")
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
