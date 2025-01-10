# frozen_string_literal: true

require "date"

# A useful extension used by Derivatives and the driver script
class Date
  def last_of_month?
    next_day.month != month
  end

  def first_of_month?
    day == 1
  end
end

module PostZephirProcessing
  # A class that determines the "dates of interest" when looking at directories
  # full of Zephir derivative files.
  #
  # NOTE: these are "run dates" and not file datestamps.
  # The Derivative subclasses will use appropriate deltas to derive datestamps.
  #
  # `Dates.new.all_dates` calculates an array of Dates from the first of the month up to today, inclusive.
  class Dates
    attr_reader :date

    # @param date [Date] the "run date"
    def initialize(date: Date.today)
      @date = date
    end

    # The standard start date (last of month) to "present"
    # @return [Array<Date>] sorted ASC
    def all_dates
      @all_dates ||= (first_of_month..date).to_a.sort
    end

    # The first of the month, relative to the "run date"
    # @return [Date]
    def first_of_month
      Date.new(date.year, date.month, 1)
    end
  end
end
