# frozen_string_literal: true

require "tmpdir"

module PostZephirProcessing
  RSpec.describe(MonthlyInventory) do
    around(:each) do |example|
      Dir.mktmpdir do |tmpdir|
        setup_test_dirs(parent_dir: tmpdir)
        setup_test_files(date: Date.parse("2023-10-30"))
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

      it "has a full inventory" do
        expect(described_class.new.full_inventory).to be_an_instance_of(Hash)
      end

      it "has an update inventory" do
        expect(described_class.new.update_inventory).to be_an_instance_of(Hash)
      end
    end

    describe "#date" do
      it "returns a Date" do
        expect(described_class.new.date).to be_an_instance_of(Date)
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

    describe "#all_dates" do
      context "with a date before the last of the month" do
        it "returns a range of more than one date" do
          (1..30).each do |day|
            date = Date.new(2023, 10, day)
            expect(described_class.new(date: date).all_dates.count).to be > 1
          end
        end
      end

      context "with the last of the month" do
        it "returns only the reference date" do
          date = Date.new(2023, 10, 31)
          expect(described_class.new(date: date).all_dates).to eq [date]
        end
      end
    end
  end
end
