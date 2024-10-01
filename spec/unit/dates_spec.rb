# frozen_string_literal: true

module PostZephirProcessing
  RSpec.describe(Dates) do
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
