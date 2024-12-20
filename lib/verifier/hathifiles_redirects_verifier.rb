# frozen_string_literal: true

require "verifier"

module PostZephirProcessing
  class HathifilesRedirectsVerifier < Verifier
    attr_reader :current_date

    REDIRECTS_REGEX = /^\d{9}\t\d{9}$/
    HISTORY_FILE_KEYS = ["recid", "mrs", "entries", "json_class"]

    def initialize(date: Date.today)
      super()
      @current_date = date
    end

    def run_for_date(date:)
      super
      @current_date = date
      verify_redirects
    end

    def verify_redirects(date: current_date)
      verify_redirects_file
      verify_redirects_history_file
    end

    def verify_redirects_file(path: redirects_file)
      return unless verify_file(path: path)
      # check that each line in the file matches regex
      Zlib::GzipReader.open(path, encoding: "utf-8").each_line.with_index(1) do |line, i|
        unless REDIRECTS_REGEX.match?(line)
          report_malformed(file: redirects_file, line: line, line_number: i)
        end
      end
    end

    def verify_redirects_history_file(path: redirects_history_file)
      return unless verify_file(path: path)

      Zlib::GzipReader.open(path, encoding: "utf-8").each_line.with_index(1) do |line, i|
        parsed = JSON.parse(line)
        # Check that the line parses to a hash
        unless parsed.instance_of?(Hash)
          report_malformed(file: redirects_history_file, line: line, line_number: i)
          next
        end
        # Check that the outermost level of keys in the JSON line are what we expect
        unless HISTORY_FILE_KEYS & parsed.keys == HISTORY_FILE_KEYS
          report_malformed(file: redirects_history_file, line: line, line_number: i)
          next
        end
        # here we could go further and verify deeper structure of json,
        # but not sure it's worth it?
      rescue JSON::ParserError
        report_malformed(file: redirects_history_file, line: line, line_number: i)
      end
    end

    # These are simple enough that Derivative subclasses would be overkill
    def redirects_file(date: current_date)
      File.join(ENV["REDIRECTS_DIR"], "redirects_#{date.strftime("%Y%m")}.txt.gz")
    end

    def redirects_history_file(date: current_date)
      File.join(ENV["REDIRECTS_HISTORY_DIR"], "#{date.strftime("%Y%m")}.ndj.gz")
    end

    private

    def report_malformed(file:, line:, line_number:)
      error(message: "#{file}:#{line_number} contains malformed line: #{line}")
    end
  end
end
