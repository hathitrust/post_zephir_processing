# frozen_string_literal: true

require "dates"
require "derivative"
require "derivative/catalog"
require "derivative/delete"
require "derivative/rights"

module PostZephirProcessing
  # A class that knows the expected locations of standard Zephir derivative files.
  # `earliest_missing_date` is the main entrypoint when constructing an agenda of Zephir
  # file dates to fetch for processing.
  class PostZephirDerivatives
    attr_reader :dates

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
