# frozen_string_literal: true

require "faraday"
require "verifier"
require "derivatives"

# Verifies that catalog indexing workflow stage did what it was supposed to.

module PostZephirProcessing
  class CatalogIndexVerifier < Verifier
    def verify_index_count(derivative:)
      catalog_linecount = gzip_linecount(path: derivative.path)

      if derivative.full?
        solr_count = solr_nondeleted_records
        query_desc = "existed"
      else
        date_of_indexing = derivative.date + 1
        solr_count = solr_count(date_of_indexing)
        query_desc = "had time_of_indexing on #{date_of_indexing}"
      end

      # in normal operation, we _should_ have indexed this the day after the
      # date listed in the file.
      #
      # could potentially use the journal to determine when we actually
      # indexed it?
      if solr_count < catalog_linecount
        error(message: "#{derivative.path} had #{catalog_linecount} records, but only #{solr_count} #{query_desc} in solr")
      end
    end

    def solr_count(date_of_indexing)
      datebegin = date_of_indexing.to_time.utc.strftime("%FT%TZ")
      solr_result_count("time_of_index:[#{datebegin}%20TO%20NOW]")
    end

    def solr_nondeleted_records
      solr_result_count("deleted:false")
    end

    def solr_result_count(filter_query)
      url = "#{ENV["SOLR_URL"]}/select?fq=#{filter_query}&q=*:*&rows=0&wt=json"

      JSON.parse(Faraday.get(url).body)["response"]["numFound"]
    end

    def run_for_date(date:)
      # The dates on the files are the previous day, but the indexing
      # happens on the current day. When we verify the current day, we are
      # verifying that the file named for the _previous_ day was produced.

      @current_date = date
      Derivative::CatalogArchive.derivatives_for_date(date: date - 1).each do |derivative|
        path = derivative.path

        if verify_file(path: path)
          verify_index_count(derivative: derivative)
        end
      end
    end
  end
end
