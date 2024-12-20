require "derivative"

module PostZephirProcessing
  class Derivative::Delete < Derivative
    def initialize(date:, full: false)
      raise ArgumentError, "'deletes' has no full version" if full
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
        location: ENV["CATALOG_PREP"],
        name: "zephir_upd_YYYYMMDD_delete.txt.gz"
      }
    end
  end
end
