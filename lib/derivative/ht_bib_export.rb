require "derivative"

module PostZephirProcessing
  class Derivative::HTBibExport < Derivative
    def template
      {
        location: ENV["ZEPHIR_DATA"],
        name: "ht_bib_export_full_YYYY-MM-DD.json.gz"
      }
    end
  end
end
