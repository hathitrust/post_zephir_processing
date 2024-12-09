# frozen_string_literal: true

require "zlib"
require_relative "../verifier"
require_relative "../derivatives"

# Verifies that catalog indexing workflow stage did what it was supposed to.

module PostZephirProcessing
  class CatalogIndexVerifier < Verifier
  end
end
