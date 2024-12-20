require "verifier"

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

    # Difference in days between when the workflow/verifier is run, and the datestamp on the files.
    # Post-zephir derivatives are datestamped yesterday relative to the run date.
    # Everything else is same day (the default).
    def datestamp_delta
      0
    end

    def datestamp
      date + datestamp_delta
    end

    def path
      File.join(
        template[:location],
        datestamped_file
      )
    end

    def datestamped_file
      template[:name].sub(/YYYYMMDD/i, datestamp.strftime("%Y%m%d"))
        .sub(/YYYY-MM-DD/i, datestamp.strftime("%Y-%m-%d"))
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
