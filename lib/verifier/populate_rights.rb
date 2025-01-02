# frozen_string_literal: true

require "verifier"
require "derivative/rights"

module PostZephirProcessing
  # The PostZephirVerifier checks for the existence and readability of the .rights files.
  # This class is responsible for verifying that the content has been addressed properly.

  # Specifically, we can make sure each HTID in the rights file(s) for the reference date
  # exist in ht_rights.rights_current.

  # CRMS, licensing, takedowns, etc can prevent .rights entries from being inserted;
  # however, each HTID must exist in the database regardless of whether this particular
  # run has made a change.

  # We may also look for errors in the output logs (postZephir.pm and/or populate_rights_data.pl?)
  # but that is out of scope for now.
  class Verifier::PopulateRights < Verifier
    # This is an efficient slice size we adopted for hathifiles based on experimental evidence
    DEFAULT_SLICE_SIZE = 10_000
    attr_reader :slice_size

    def initialize(slice_size: DEFAULT_SLICE_SIZE)
      @slice_size = slice_size
      super()
    end

    def run_for_date(date:)
      super
      Derivative::Rights.derivatives_for_date(date: date).each do |derivative|
        path = derivative.path
        next unless verify_file(path: path)
        verify_rights_file(path: path)
      end
    end

    # Check each entry in the .rights file for an entry in `rights_current`.
    def verify_rights_file(path:)
      File.open(path) do |infile|
        slice = Set.new
        infile.each_line do |line|
          line.strip!
          slice << line.split("\t").first
          if slice.count >= slice_size
            find_missing_rights(htids: slice)
            slice.clear
          end
        end
        if slice.count.positive?
          find_missing_rights(htids: slice)
        end
      end
    end

    private

    # @param htids [Set<String>] a Set of HTID strings to check against the database
    # @return (not defined)
    def find_missing_rights(htids:)
      db_htids = Set.new
      split_htids = htids.map { |htid| htid.split(".", 2) }
      Services[:database][:rights_current]
        .select(:namespace, :id)
        .where([:namespace, :id] => split_htids)
        .each do |record|
        db_htids << record[:namespace] + "." + record[:id]
      end
      (htids - db_htids).each do |htid|
        error message: "missing rights_current for #{htid}"
      end
    end
  end
end
