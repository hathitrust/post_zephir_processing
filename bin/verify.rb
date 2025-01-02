#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib/", __FILE__)
require "dotenv"
require "verifier/post_zephir"
require "verifier/populate_rights"
require "verifier/hathifiles"
require "verifier/hathifiles_database"
require "verifier/hathifiles_listing"
require "verifier/hathifiles_redirects"
require "verifier/catalog_index"

Dotenv.load(File.join(ENV.fetch("ROOTDIR"), "config", "env"))

module PostZephirProcessing
  def self.run_verifiers(date_to_check)
    [
      Verifier::PostZephir,
      Verifier::PopulateRights,
      Verifier::Hathifiles,
      Verifier::HathifilesDatabase,
      Verifier::HathifilesListing,
      Verifier::HathifilesRedirects,
      Verifier::CatalogIndex
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
