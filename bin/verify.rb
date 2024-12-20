#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib/", __FILE__)
require "dotenv"
require "verifier/post_zephir_verifier"
require "verifier/populate_rights_verifier"
require "verifier/hathifiles_verifier"
require "verifier/hathifiles_database_verifier"
require "verifier/hathifiles_listing_verifier"
require "verifier/hathifiles_redirects_verifier"
require "verifier/catalog_index_verifier"

Dotenv.load(File.join(ENV.fetch("ROOTDIR"), "config", "env"))

module PostZephirProcessing
  def self.run_verifiers(date_to_check)
    [
      # all outputs here are date-stamped with yesterday's date
      -> { PostZephirVerifier.new.run_for_date(date: date_to_check - 1) },
      -> { PopulateRightsVerifier.new.run_for_date(date: date_to_check - 1) },

      # these are today's date
      -> { HathifilesVerifier.new.run_for_date(date: date_to_check) },
      -> { HathifilesDatabaseVerifier.new.run_for_date(date: date_to_check) },
      -> { HathifilesListingVerifier.new.run_for_date(date: date_to_check) },
      -> { HathifileRedirectsVerifier.new.run_for_date(date: date_to_check) },
      -> { CatalogIndexVerifier.new.run_for_date(date: date_to_check) },
    ].each do |verifier_lambda|
      begin
        verifier_lambda.call
        # Very simple minded exception handler so we can in theory check subsequent workflow steps
      rescue StandardError => e
        Services[:logger].fatal e
      end
    end
  end
end

date_to_check = ARGV[0] || Date.today
PostZephirProcessing.run_verifiers(date_to_check) if __FILE__ == $0
