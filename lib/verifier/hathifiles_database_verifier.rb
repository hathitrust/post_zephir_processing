# frozen_string_literal: true

require "zlib"

require_relative "../verifier"
require_relative "../derivatives"

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

    def self.gzip_linecount(path:)
      Zlib::GzipReader.open(path, encoding: "utf-8") { |gz| gz.count }
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
      if File.exist?(update_file)
        if !self.class.has_log?(hathifile: update_file)
          error message: "missing hf_log: no entry for daily #{update_file}"
        end
      end
      if current_date.first_of_month?
        full_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_full_YYYYMMDD.txt.gz", date: current_date)
        if File.exist?(full_file)
          if !self.class.has_log?(hathifile: full_file)
            error message: "missing hf_log: no entry for monthly #{full_file}"
          end
        end
      end
    end

    def verify_hathifiles_database_count
      if current_date.first_of_month?
        if File.exist?(full_file)
          full_file_count = self.class.gzip_linecount(path: full_file)
          db_count = self.class.db_count
          if full_file_count > db_count
            error message: "hf count mismatch: #{full_file} (#{full_file_count}) vs hathifiles.hf (#{db_count})"
          end
        end
      end
    end

    def update_file
      self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_upd_YYYYMMDD.txt.gz", date: current_date)
    end

    def full_file
      self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_full_YYYYMMDD.txt.gz", date: current_date)
    end
  end
end
