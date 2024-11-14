# frozen_string_literal: true

require_relative "../verifier"
require_relative "../derivatives"

# Verifies that post_zephir workflow stage did what it was supposed to.

# TODO: document and verify the files written by monthly process.
# They should be mostly the same but need to be accounted for.

module PostZephirProcessing
  class PostZephirVerifier < Verifier
    # TODO: do we need to check any non-datestamped files for this date?
    # Review README list of derivatives in TMPDIR
    # def run_for_dates(dates: journal.dates)
    # end

    def run_for_date(date:)
      datestamped_derivatives(date).each do |path|
        verify_file(path: path)
      end
    end

    private

    # TODO: see if we want to move this to Derivatives class
    def datestamped_derivative(location:, name:, date:)
      File.join(
        Derivatives.directory_for(location: location),
        self.class.datestamped_file(name: "zephir_upd_YYYYMMDD.json.gz", date: date)
      )
    end

    def datestamped_derivatives(date)
      [
        datestamped_derivative(location: :CATALOG_ARCHIVE, name: "zephir_upd_YYYYMMDD.json.gz", date: date),
        datestamped_derivative(location: :CATALOG_PREP, name: "zephir_upd_YYYYMMDD.json.gz", date: date),
        datestamped_derivative(location: :CATALOG_PREP, name: "zephir_upd_YYYYMMDD_delete.txt.gz", date: date),
        datestamped_derivative(location: :RIGHTS_DIR, name: "zephir_upd_YYYYMMDD.rights", date: date),
        datestamped_derivative(location: :TMPDIR, name: "vufind_incremental_YYYY-MM-DD_dollar_dup.txt.gz", date: date)
      ]
    end
  end
end
