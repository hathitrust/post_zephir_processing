require "derivative"

module PostZephirProcessing
  class Derivative::Delete < Derivative
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
        location: ENV["CATALOG_PREP"],
        name: "zephir_upd_YYYYMMDD_delete.txt.gz"
      }
    end
  end
end
