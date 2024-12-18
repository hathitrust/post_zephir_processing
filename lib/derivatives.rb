# frozen_string_literal: true

require_relative "dates"
require "derivative"
require "derivative/catalog"
require "derivative/delete"
require "derivative/rights"

module PostZephirProcessing
  # A class that knows the expected locations of standard Zephir derivative files.
  # `earliest_missing_date` is the main entrypoint when constructing an agenda of Zephir
  # file dates to fetch for processing.
  #
  # TODO: this class may be renamed PostZephirDerivatives once directory_for is updated,
  # moved, or elimminated.
  class Derivatives
    # TODO: STANDARD_LOCATIONS is only used for testing directory_for and may be eliminated.
    STANDARD_LOCATIONS = [
      :CATALOG_ARCHIVE,
      :CATALOG_PREP,
      :RIGHTS_ARCHIVE,
      :TMPDIR,
      :WWW_DIR
    ].freeze

    attr_reader :dates

    # Translate a known file destination as an environment variable key
    # into the path via ENV or a default.
    # @return [String] path to the directory
    def self.directory_for(location:)
      location = location.to_s
      case location

      when "CATALOG_ARCHIVE", "HATHIFILE_ARCHIVE", "CATALOG_PREP", "INGEST_BIBRECORDS", "RIGHTS_DIR", "WWW_DIR", "ZEPHIR_DATA"
        ENV.fetch location
      when "RIGHTS_ARCHIVE"
        ENV["RIGHTS_ARCHIVE"] || File.join(ENV.fetch("RIGHTS_DIR"), "archive")
      when "TMPDIR"
        ENV["TMPDIR"] || File.join(ENV.fetch("DATA_ROOT"), "work")
      else
        raise "Unknown location #{location.inspect}"
      end
    end

    # @param date [Date] the file datestamp date, not the "run date"
    def initialize(date: (Date.today - 1))
      @dates = Dates.new(date: date)
    end

    # @return [Date,nil]
    def earliest_missing_date
      derivative_classes = [
        Derivative::CatalogPrep,
        Derivative::Rights,
        Derivative::Delete
      ]
      earliest = nil
      dates.all_dates.each do |date|
        derivative_classes.each do |klass|
          klass.derivatives_for_date(date: date).each do |derivative|
            if !File.exist?(derivative.path)
              earliest = [earliest, date].compact.min
            end
          end
        end
      end
      earliest
    end
  end
end
