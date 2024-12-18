require "derivative"

module PostZephirProcessing
  class Derivative::Rights < Derivative
    def self.derivatives_for_date(date:)
      derivatives = [
        new(
          full: false,
          date: date
        )
      ]

      if date.last_of_month?
        derivatives << new(
          full: true,
          date: date
        )
      end

      derivatives
    end

    def template
      {
        location: :RIGHTS_ARCHIVE,
        name: "zephir_#{fullness}_YYYYMMDD.rights"
      }
    end
  end
end
