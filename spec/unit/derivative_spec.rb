# frozen_string_literal: true

require "derivative"

module PostZephirProcessing
  RSpec.describe(Derivative) do
    let(:test_date_first_of_month) { Date.parse("2023-11-01") }
    # let(:test_date_last_of_month) { Date.parse("2023-11-30") }

    let(:params) do
      {
        date: test_date_first_of_month,
        full: true
      }
    end
    let(:derivative) { described_class.new(**params) }

    describe "#initialize" do
      it "requires a date and a fullness" do
        expect(derivative).to be_an_instance_of(Derivative)
      end
    end

    it "reports back its fullness" do
      expect(derivative.full?).to be true
    end
  end
end
