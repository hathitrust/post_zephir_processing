require "derivative"

module PostZephirProcessing
  class Derivative::IngestBibrecord < Derivative
    attr_reader :name

    def initialize(name:)
      @name = name
    end

    def path
      File.join(ENV["INGEST_BIBRECORDS"], name)
    end

    def self.derivatives_for_date(date:)
      if date.last_of_month?
        [
          new(name: "groove_full.tsv.gz"),
          new(name: "zephir_ingested_items.txt.gz")
        ]
      else
        []
      end
    end
  end
end
