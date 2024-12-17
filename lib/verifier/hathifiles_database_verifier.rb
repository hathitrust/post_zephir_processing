# frozen_string_literal: true

require "zlib"

require_relative "../verifier"
require_relative "../derivatives"
require_relative "../derivative"

module PostZephirProcessing
  class HathifilesDatabaseVerifier < Verifier
    attr_reader :current_date

    # Does an entry exist in hf_log for the hathifile?
    # Can pass a path or just the filename.
    def self.has_log?(hathifile:)
      PostZephirProcessing::Services[:database][:hf_log]
        .where(hathifile: File.basename(hathifile))
        .count
        .positive?
    end

    # Count the number of entries in hathifiles.hf
    def self.db_count
      PostZephirProcessing::Services[:database][:hf].count
    end

    def run_for_date(date:)
      @current_date = date
      verify_hathifiles_database_log
      verify_hathifiles_database_count
    end

    private

    def verify_hathifiles_database_log
      # File missing? Not our problem, should be caught by earlier verifier.

      Derivative.derivatives_for_date(date: current_date, derivative_type: :hathifile).each do |d|
        next unless File.exist?(d.path)

        if !self.class.has_log?(hathifile: d.path)
          error message: "missing hf_log: no entry for #{d.path}"
        end
      end
    end

    def verify_hathifiles_database_count
      Derivative.derivatives_for_date(date: current_date, derivative_type: :hathifile).select { |d| d.full? }.each do |full_file|
        next unless File.exist?(full_file.path)

        full_file_count = gzip_linecount(path: full_file.path)
        db_count = self.class.db_count
        if full_file_count > db_count
          error message: "hf count mismatch: #{full_file.path} (#{full_file_count}) vs hathifiles.hf (#{db_count})"
        end
      end
    end
  end
end
