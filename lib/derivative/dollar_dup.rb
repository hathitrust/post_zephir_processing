require "derivative"

module PostZephirProcessing
  class Derivative::DollarDup < Derivative
    def initialize(date:, full: false)
      raise ArgumentError, "'dollar dup' has no full version" if full
      super
    end

    def self.derivatives_for_date(date:)
      [
        new(
          full: false,
          date: date
        )
      ]
    end

    def template
      {
        location: :TMPDIR,
        name: "vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz"
      }
    end
  end
end
