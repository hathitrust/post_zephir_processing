require "derivative"

module PostZephirProcessing
  class Derivative::Hathifile < Derivative
    def self.derivatives_for_date(date:)
      derivatives = [
        Derivative::Hathifile.new(
          full: false,
          date: date
        )
      ]

      if date.first_of_month?
        derivatives << Derivative::Hathifile.new(
          full: true,
          date: date
        )
      end

      derivatives
    end

    def template
      {
        location: ENV["HATHIFILE_ARCHIVE"],
        name: "hathi_#{fullness}_YYYYMMDD.txt.gz"
      }
    end
  end
end
