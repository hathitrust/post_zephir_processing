require "derivative"

module PostZephirProcessing
  class HathifileDerivative < Derivative
    def self.derivatives_for_date(date:)
      derivatives = [
        HathifileDerivative.new(
          full: false,
          date: date
        )
      ]

      if date.first_of_month?
        derivatives << HathifileDerivative.new(
          full: true,
          date: date
        )
      end

      derivatives
    end

    def template
      {
        location: :HATHIFILE_ARCHIVE,
        name: "hathi_#{fullness}_YYYYMMDD.txt.gz"
      }
    end
  end
end
