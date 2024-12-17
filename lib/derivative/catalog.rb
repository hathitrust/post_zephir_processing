require "derivative"

module PostZephirProcessing
  class Derivative::Catalog < Derivative
    def self.derivatives_for_date(date:)
      derivatives = [
        new(
          full: false,
          date: date
        )
      ]

      if date.last_of_month?
        derivatives << new(
          full: true,
          date: date
        )
      end

      derivatives
    end

    def template
      {
        location: location,
        name: filename_template
      }
    end

    private

    def filename_template
      if full
        "zephir_full_YYYYMMDD_vufind.json.gz"
      else
        "zephir_upd_YYYYMMDD.json.gz"
      end
    end
  end

  class Derivative::CatalogArchive < Derivative::Catalog
    def location
      :CATALOG_ARCHIVE
    end
  end

  class Derivative::CatalogPrep < Derivative::Catalog
    def location
      :CATALOG_PREP
    end
  end
end
