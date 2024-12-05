#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv"
require_relative "../lib/verifier/hathifiles_verifier"
require_relative "../lib/verifier/populate_rights_verifier"
require_relative "../lib/verifier/post_zephir_verifier"

Dotenv.load(File.join(ENV.fetch("ROOTDIR"), "config", "env"))

[
  PostZephirProcessing::PostZephirVerifier,
  PostZephirProcessing::PopulateRightsVerifier,
  PostZephirProcessing::HathifilesVerifier
].each do |klass|
  begin
    klass.new.run
  # Very simple minded exception handler so we can in theory check subsequent workflow steps
  rescue StandardError => e
    PostZephirProcessing::Services[:logger].fatal e
  end
end
