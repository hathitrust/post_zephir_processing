require "derivative"

module PostZephirProcessing
  # These derivatives are the files downloaded from Zephir.
  # They are not checked explicitly for well-formedness
  # (to do so, must define self.derivatives_for_date);
  # however, catalog archive checks line counts against these as originals
  # so this class allows the downloads to be located.
  #
  # We might want to reconsider keeping the "incr" files in TMPDIR
  # and instead move them to the same location as the full files.
  class Derivative::HTBibExport < Derivative
    def datestamp_delta
      -1
    end

    # These files are unusual in that they live in two different locations:
    # the monthlies get moved but the updates just get downloaded and left in place.
    def template
      if full?
        {
          location: ENV["ZEPHIR_DATA"],
          name: "ht_bib_export_full_YYYY-MM-DD.json.gz"
        }
      else
        {
          location: ENV["TMPDIR"],
          name: "ht_bib_export_incr_YYYY-MM-DD.json.gz"
        }
      end
    end
  end
end
