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
      update_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_upd_YYYYMMDD.txt.gz", date: current_date)
      if !self.class.has_log?(hathifile: update_file)
        error "no hf_log entry for #{update_file}"
      end
    end

    def verify_hathifiles_database_count
      # first of month
      if current_date.day == 1
        full_file = self.class.dated_derivative(location: :HATHIFILE_ARCHIVE, name: "hathi_full_YYYYMMDD.txt.gz", date: current_date)
        full_file_count = self.class.gzip_linecount(path: full_file)
        db_count = self.class.db_count
        if full_file_count < db_count
          error "#{full_file} has #{full_file_count} rows but hathifiles.hf has #{db_count}"
        end
      end
    end
  end
end
