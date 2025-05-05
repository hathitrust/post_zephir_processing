# frozen_string_literal: true

require "verifier"
require "derivative/hathifile_www"
require "json"

module PostZephirProcessing
  class Verifier::HathifilesListing < Verifier
    attr_reader :current_date

    def run_for_date(date:)
      super
      @current_date = date
      verify_hathifiles_listing
    end

    def verify_hathifiles_listing(date: current_date)
      Derivative::HathifileWWW.derivatives_for_date(date: date).each do |hathifile_derivative|
        verify_listing(path: hathifile_derivative.path)
      end
    end

    def verify_listing(path:)
      verify_file(path: path)
      verify_file_in_json(filename: File.basename(path))
    end

    def verify_file_in_json(filename:)
      unless listings.include?(filename)
        error(message: "No listing with filename: #{filename} in #{Derivative::HathifileWWW.json_path}")
      end
    end

    private

    # Load json file and produce the set of "filename" values in that json, once.
    def listings
      @listings ||= JSON
        .load_file(Derivative::HathifileWWW.json_path)
        .map { |listing| listing["filename"] }
        .to_set
    end
  end
end
