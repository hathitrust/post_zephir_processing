# frozen_string_literal: true

require "date"
require "yaml"

module PostZephirProcessing
  class Journal
    JOURNAL_NAME = "journal.yml"
    attr_reader :dates

    def self.from_yaml
      new(dates: YAML.load_file(destination_path))
    end

    # It is okay to clobber last run's journal. The journal is not datestamped.
    def self.destination_path
      File.join(ENV["DATA_ROOT"], JOURNAL_NAME)
    end

    # It is okay to initialize and write a journal with no dates.
    # Can be called with a Range as long as it is bounded.
    def initialize(dates: [])
      @dates = dates.map do |date|
        date.is_a?(String) ? Date.parse(date) : date
      end.sort
    end

    def write!(path: self.class.destination_path)
      File.write(path, @dates.map(&method(:to_yyyymmdd)).to_yaml)
    end

    private

    def to_yyyymmdd(date)
      date.strftime "%Y%m%d"
    end
  end
end
