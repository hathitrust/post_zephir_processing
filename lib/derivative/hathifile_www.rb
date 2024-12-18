require "derivative"

module PostZephirProcessing
  class Derivative::HathifileWWW < Derivative
    def self.derivatives_for_date(date:)
      derivatives = [
        Derivative::HathifileWWW.new(
          full: false,
          date: date
        )
      ]

      if date.first_of_month?
        derivatives << Derivative::HathifileWWW.new(
          full: true,
          date: date
        )
      end

      derivatives
    end

    def self.json_path
      File.join(ENV["WWW_DIR"], "hathi_file_list.json")
    end

    def template
      {
        location: :WWW_DIR,
        name: "hathi_#{fullness}_YYYYMMDD.txt.gz"
      }
    end
  end
end
