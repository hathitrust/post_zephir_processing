require "verifier"
require "derivatives"

module PostZephirProcessing
  class Derivative
    attr_reader :date, :full, :derivative_type

    def initialize(date:, full:, derivative_type:)
      @date = date
      @full = full
      @derivative_type = derivative_type
    end

    def full?
      full
    end

    def path
      Verifier.dated_derivative(**template, date: date)
    end

    def self.derivatives_for_date(date:, derivative_type:)
      raise unless derivative_type == :hathifile

      derivatives = [
        Derivative.new(
          derivative_type: :hathifile,
          full: false,
          date: date
        )
      ]

      if date.first_of_month?
        derivatives << Derivative.new(
          derivative_type: :hathifile,
          full: true,
          date: date
        )
      end

      derivatives
    end

    private

    def fullness
      if full
        "full"
      else
        "upd"
      end
    end

    # given derivative type, knows how to construct params for Verifier.dated_derivative
    def template
      case derivative_type
      when :hathifile
        {location: :HATHIFILE_ARCHIVE, name: "hathi_#{fullness}_YYYYMMDD.txt.gz"}
      end
    end
  end
end
