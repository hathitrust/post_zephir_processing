# frozen_string_literal: true

require "journal"
require "services"

# Common superclass for all things Verifier.

module PostZephirProcessing
  class Verifier
    attr_reader :errors

    def initialize
      # Mainly for testing
      @errors = []
    end

    # Verify all dates listed in the journal
    def run
      Journal.from_yaml.dates.each do |date|
        run_for_date(date: date)
      end
    end

    # Verify outputs for one date.
    # Useful for verifying datestamped files.
    def run_for_date(date:)
      info message: "running for #{date}"
    end

    # Basic checks for the existence and readability of the file at `path`.
    # @return [Boolean] `true` if verified, `false` if error was reported.
    def verify_file(path:)
      info message: "verifying file exists & is readable: #{path}"
      verify_file_exists(path: path) && verify_file_readable(path: path)
    end

    # @return [Boolean] `true` if verified, `false` if error was reported.
    def verify_file_exists(path:)
      File.exist?(path).tap do |exists|
        error(message: "not found: #{path}") unless exists
      end
    end

    # @return [Boolean] `true` if verified, `false` if error was reported.
    def verify_file_readable(path:)
      File.readable?(path).tap do |readable|
        error(message: "not readable: #{path}") unless readable
      end
    end

    def gzip_linecount(path:)
      info message: "getting line count: #{path}"
      Zlib::GzipReader.open(path, encoding: "utf-8") { |gz| gz.count }
    end

    # Take a .ndj.gz file and check that each line is indeed parseable json
    # @return [Boolean] `true` if verified, `false` if error was reported.
    def verify_parseable_ndj(path:)
      info message: "verifying parseable newline-delimited json: #{path}"
      Zlib::GzipReader.open(path, encoding: "utf-8") do |gz|
        gz.each_line do |line|
          JSON.parse(line)
        end
      rescue JSON::ParserError
        error(message: "File #{path} contains unparseable JSON")
        return false
      end
      true
    end

    # Log an error -- something unexpected from the verifier. Generally, this
    # indicates something unexpected that requires human intervention to
    # correct, and which should be corrected ASAP.
    def error(message:)
      output_msg = self.class.to_s + ": " + message
      @errors << output_msg
      Services[:logger].error output_msg
    end

    def info(message:)
      Services[:logger].info "#{self.class}: #{message}"
    end
  end
end
