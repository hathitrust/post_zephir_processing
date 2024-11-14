#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/verifier/post_zephir_verifier"

[
  PostZephirProcessing::PostZephirVerifier
].each do |klass|
  klass.new.run
end
