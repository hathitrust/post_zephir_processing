# frozen_string_literal: true

require_relative "journal"
require_relative "services"

# Common superclass for all things Verifier.
# Right now the only thing I can think of to put here is shared
# code for writing whatever output file, logs, metrics, artifacts, etc. we decide on.

module PostZephirProcessing
  class Verifier
    attr_reader :journal

    def self.datestamped_file(name:, date:)
      name.sub(/YYYYMMDD/i, date.strftime("%Y%m%d"))
        .sub(/YYYY-MM-DD/i, date.strftime("%Y-%m-%d"))
    end

    # Generally, needs a Journal in order to know what to look for.
    def initialize
      @journal = Journal.from_yaml
    end

    # Main entrypoint
    # What should it return?
    # Do we want to bail out or keep going if we encounter a show-stopper?
    # I'm inclined to just keep going.
    def run
      run_for_dates
      journal.dates.each do |date|
        run_for_date(date: date)
      end
    end

    # Subclasses can verify outputs that are not datestamped, in case we want to
    # avoid running an expensive check multiple times.
    # This may not be needed.
    def run_for_dates(dates: journal.dates)
    end

    # Verify outputs for one date in the journal.
    # USeful for verifying datestamped files.
    def run_for_date(date:)
    end

    # Basic check(s) for the existence of the file at `path`.
    # We should do whatever logging/warning we want to do if the file does
    # not pass muster.
    # At least call File.exist?
    # What about permissions?
    # Verifying contents is out of scope.
    def verify_file(path:)
      if !File.exist? path
        Services[:logger].error "not found: #{path}"
      end
    end
  end
end
