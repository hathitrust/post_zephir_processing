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

    def datestamp_delta
      -1
    end

    def template
      {
        location: ENV["TMPDIR"] || File.join(ENV["DATA_ROOT"], "work"),
        name: "vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz"
      }
    end
  end
end
