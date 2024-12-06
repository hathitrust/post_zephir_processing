# frozen_string_literal: true

require_relative "../verifier"
require_relative "../derivatives"

module PostZephirProcessing
  class HathifilesListingVerifier < Verifier
    attr_reader :current_date

    def run_for_date(date:)
      @current_date = date
      verify_hathifiles_listing
    end

    def verify_hathifiles_listing(date: current_date)
      derivatives_for_date(date: date).each do |derivative_path|
        verify_listing(path: derivative_path)
      end
    end

    def derivatives_for_date(date:)
      derivatives = [
        self.class.dated_derivative(
          location: :WWW_DIR,
          name: "hathi_upd_YYYYMMDD.txt.gz",
          date: date
        )
      ]

      if date.first_of_month?
        derivatives << self.class.dated_derivative(
          location: :WWW_DIR,
          name: "hathi_full_YYYYMMDD.txt.gz",
          date: date
        )
      end

      derivatives
    end

    def verify_listing(path:)
      verify_file(path: path)
    end
  end
end
