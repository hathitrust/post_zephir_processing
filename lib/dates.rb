# frozen_string_literal: true

require "date"

# A useful extension used by Derivatives and the driver script
class Date
  def last_of_month?
    next_day.month != month
  end
end

module PostZephirProcessing
  # A class that determines the filename "dates of interest" when looking at directories
  # full of Zephir derivative files.
  # `Dates.new.all_dates` calculates an array of Dates from the most recent
  # last day of the month up to yesterday, inclusive.
  class Dates
    attr_reader :date

    # @param date [Date] the file datestamp date, not the "run date", yesterday by default
    def initialize(date: (Date.today - 1))
      @date = date
    end

    # The standard start date (last of month) to "present"
    # @return [Array<Date>] sorted ASC
    def all_dates
      @all_dates ||= (start_date..date).to_a.sort
    end

    # The most recent last day of the month (which may be today)
    # @return [Date]
    def start_date
      @start_date ||= if date.last_of_month?
        date
      else
        Date.new(date.year, date.month, 1) - 1
      end
    end
  end
end
