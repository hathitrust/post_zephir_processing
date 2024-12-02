# frozen_string_literal: true

require_relative "derivatives"
require_relative "journal"
require_relative "services"

# Common superclass for all things Verifier.
# Right now the only thing I can think of to put here is shared
# code for writing whatever output file, logs, metrics, artifacts, etc. we decide on.

module PostZephirProcessing
  class Verifier
    attr_reader :journal, :errors

    def self.datestamped_file(name:, date:)
      name.sub(/YYYYMMDD/i, date.strftime("%Y%m%d"))
        .sub(/YYYY-MM-DD/i, date.strftime("%Y-%m-%d"))
    end

    # TODO: see if we want to move this to Derivatives class
    def self.dated_derivative(location:, name:, date:)
      File.join(
        Derivatives.directory_for(location: location),
        datestamped_file(name: name, date: date)
      )
    end

    # TODO: see if we want to move this to Derivatives class
    def self.derivative(location:, name:)
      File.join(Derivatives.directory_for(location: location), name)
    end

    # Generally, needs a Journal in order to know what to look for.
    def initialize
      @journal = Journal.from_yaml
      # Mainly for testing
      @errors = []
    end

    # Main entrypoint
    # What should it return?
    # Do we want to bail out or keep going if we encounter a show-stopper?
    # I'm inclined to just keep going.
    def run
      journal.dates.each do |date|
        run_for_date(date: date)
      end
    end

    # Verify outputs for one date in the journal.
    # USeful for verifying datestamped files.
    def run_for_date(date:)
    end

    # Basic checks for the existence and readability of the file at `path`.
    # We should do whatever logging/warning we want to do if the file does
    # not pass muster.
    # Verifying contents is out of scope.
    # Returns `true` if verified.
    def verify_file(path:)
      verify_file_exists(path: path) && verify_file_readable(path: path)
    end

    def verify_file_exists(path:)
      File.exist?(path).tap do |exists|
        error(message: "not found: #{path}") unless exists
      end
    end

    def verify_file_readable(path:)
      File.readable?(path).tap do |readable|
        error(message: "not readable: #{path}") unless readable
      end
    end

    # I'm not sure if we're going to try to distinguish errors and warnings.
    # For now let's call everything an error.
    def error(message:)
      @errors << message
      Services[:logger].error message
    end
  end
end
