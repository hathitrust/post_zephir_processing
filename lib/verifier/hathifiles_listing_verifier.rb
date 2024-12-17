# frozen_string_literal: true

require_relative "../verifier"
require_relative "../derivatives"
require_relative "../derivative/hathifile_www"
require "json"

module PostZephirProcessing
  class HathifilesListingVerifier < Verifier
    attr_reader :current_date

    def run_for_date(date:)
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

      filename = File.basename(path)
      verify_file_in_json(filename: filename)
    end

    # Verify that the derivatives for the date are included in
    # "#{ENV['WWW_DIR']}/hathi_file_list.json"
    def verify_file_in_json(filename:)
      json_path = "#{ENV["WWW_DIR"]}/hathi_file_list.json"
      listings = JSON.load_file(json_path)
      matches = []

      listings.each do |listing|
        if listing["filename"] == filename
          matches << listing
          break
        end
      end

      if matches.empty?
        error(message: "Did not find a listing with filename: #{filename} in JSON (#{json_path})")
      end
    end
  end
end