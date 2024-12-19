# frozen_string_literal: true

require "tmpdir"
require "post_zephir_derivatives"

module PostZephirProcessing
  RSpec.describe(PostZephirDerivatives) do
    describe ".new" do
      it "creates a PostZephirDerivatives" do
        expect(described_class.new).to be_an_instance_of(PostZephirDerivatives)
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
  end
end
