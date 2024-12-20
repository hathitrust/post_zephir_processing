# frozen_string_literal: true

require "climate_control"
require "tmpdir"

module PostZephirProcessing
  RSpec.describe(Journal) do
    around(:each) do |example|
      with_test_environment do |tmpdir|
        example.run
      end
    end

    let(:with_no_dates) { described_class.new }
    let(:unsorted_dates) { [Date.today, Date.today + 1, Date.today - 100] }
    let(:range_of_dates) { (Date.today..Date.today + 1) }
    let(:with_dates) { described_class.new(dates: unsorted_dates) }
    let(:with_range) { described_class.new(dates: range_of_dates) }

    describe ".destination_path" do
      it "contains the current DATA_ROOT" do
        expect(described_class.destination_path).to match(@tmpdir)
      end
    end

    describe ".from_yaml" do
      it "produces a Journal with the expected dates" do
        File.write(described_class.destination_path, test_journal)
        expect(described_class.from_yaml).to be_an_instance_of(Journal)
        expect(described_class.from_yaml.dates).to eq(test_journal_dates)
      end
    end

    describe ".new" do
      context "with default empty dates" do
        it "creates a Journal" do
          expect(with_no_dates).to be_an_instance_of(Journal)
        end
      end

      context "with explicit dates" do
        it "creates a Journal" do
          expect(with_dates).to be_an_instance_of(Journal)
        end
      end

      context "with a date range" do
        it "creates a Journal" do
          expect(with_range).to be_an_instance_of(Journal)
        end
      end
    end

    describe "#dates" do
      context "with default empty dates" do
        it "returns an empty Array" do
          expect(with_no_dates.dates).to eq([])
        end
      end

      context "with explicit dates" do
        it "returns a sorted array" do
          expect(with_dates.dates).to eq(unsorted_dates.sort)
        end
      end
    end

    describe "write!" do
      it "writes one YAML file to DATA_ROOT" do
        with_dates.write!
        expect(Dir.children(@tmpdir).count).to eq(1)
        expect(Dir.children(@tmpdir)[0]).to match(Journal::JOURNAL_NAME)
      end
    end
  end
end
