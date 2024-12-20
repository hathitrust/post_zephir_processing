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
      PostZephirVerifier,
      PopulateRightsVerifier,
      HathifilesVerifier,
      HathifilesDatabaseVerifier,
      HathifilesListingVerifier,
      HathifilesRedirectsVerifier,
      CatalogIndexVerifier
    ].each do |klass|
      begin
        klass.new.run_for_date(date: date_to_check)
      # Very simple minded exception handler so we can in theory check subsequent workflow steps
      rescue StandardError => e
        PostZephirProcessing::Services[:logger].fatal e
      end
    end
  end
end

date_to_check = ARGV[0] || Date.today
PostZephirProcessing.run_verifiers(date_to_check) if __FILE__ == $0
