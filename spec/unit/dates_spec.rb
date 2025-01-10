# frozen_string_literal: true

module PostZephirProcessing
  RSpec.describe(Dates) do
    describe "#all_dates" do
      context "with a date after the first of the month" do
        it "returns a range of more than one date" do
          (2..31).each do |day|
            date = Date.new(2024, 12, day)
            expect(described_class.new(date: date).all_dates.count).to be > 1
          end
        end
      end

      context "with the first of the month" do
        it "returns only the reference date" do
          date = Date.new(2024, 12, 1)
          expect(described_class.new(date: date).all_dates).to eq [date]
        end
      end
    end
  end
end
