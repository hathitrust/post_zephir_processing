require "verifier"
require "derivatives"

module PostZephirProcessing
  class Derivative
    attr_reader :date, :full

    def initialize(date:, full:)
      @date = date
      @full = full
    end

    def full?
      full
    end

    def path
      Verifier.dated_derivative(**template, date: date)
    end

    def self.derivatives_for_date(date:)
      # each subclass to return an array with all the derivatives for this date
    end

    private

    def fullness
      if full
        "full"
      else
        "upd"
      end
    end

    def template
      # each subclass to return a hash with params for Verifier.dated_derivative
    end
  end
end
