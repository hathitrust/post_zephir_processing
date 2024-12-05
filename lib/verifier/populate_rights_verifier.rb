# frozen_string_literal: true

require_relative "../verifier"
require_relative "../derivatives"

module PostZephirProcessing
  # The PostZephirVerifier checks for the existence and readability of the .rights files.
  # This class is responsible for verifying that the content has been addressed properly.

  # Specifically, we can make sure each HTID in the rights file(s) for the reference date
  # exist in ht_rights.rights_current.

  # CRMS, licensing, takedowns, etc can prevent .rights entries from being inserted;
  # however, each HTID must exist in the database regardless of whether this particular
  # run has made a change.

  # We may also look for errors in the output logs (postZephir.pm and/or populate_rights_data.pl?)
  # but thsat is out of scope for now.
  class PopulateRightsVerifier < Verifier
    FULL_RIGHTS_TEMPLATE = "zephir_full_YYYYMMDD.rights"
    UPD_RIGHTS_TEMPLATE = "zephir_upd_YYYYMMDD.rights"

    def run_for_date(date:)
      upd_path = self.class.dated_derivative(location: :RIGHTS_ARCHIVE, name: UPD_RIGHTS_TEMPLATE, date: date)
      verify_rights_file(path: upd_path)

      if date.last_of_month?
        full_path = self.class.dated_derivative(location: :RIGHTS_ARCHIVE, name: FULL_RIGHTS_TEMPLATE, date: date)
        verify_rights_file(path: full_path)
      end
    end

    # Check each entry in the .rights file for an entry in `rights_current`.
    # FIXME: this is likely to be very inefficient.
    # Should accumulate a batch of HTIDs to query all in one go.
    # See HathifileWriter#batch_extract_rights for a usable Sequel construct.
    def verify_rights_file(path:)
      db = Services[:database]
      File.open(path) do |infile|
        infile.each_line do |line|
          line.strip!
          htid = line.split("\t").first
          namespace, id = htid.split(".", 2)
          if db[:rights_current].where(namespace: namespace, id: id).count.zero?
            error message: "no entry in rights_current for #{htid}"
          end
        end
      end
    end
  end
end
