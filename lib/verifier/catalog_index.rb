# frozen_string_literal: true

require "faraday"
require "verifier"
require "derivative/catalog"
require "uri"

# Verifies that catalog indexing workflow stage did what it was supposed to.

module PostZephirProcessing
  class Verifier::CatalogIndex < Verifier
    def verify_index_count(derivative:)
      catalog_linecount = gzip_linecount(path: derivative.path)

      if derivative.full?
        solr_count = solr_nondeleted_records
        query_desc = "existed"
      else
        date_of_indexing = derivative.date
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
      solr_result_count("time_of_index:[#{datebegin} TO NOW]")
    end

    def solr_nondeleted_records
      solr_result_count("deleted:false")
    end

    def solr_result_count(filter_query)
      url = URI.parse(ENV["SOLR_URL"])
      # duplicate the URL since Faraday will mutate the passed URL to remove
      # the username & password from it ... which probably makes sense for a security
      # reason, but isn't what we want.
      conn = Faraday.new(url: url.dup)
      conn.set_basic_auth(url.user, url.password)
      params = {fq: filter_query,
                q: "*:*",
                rows: "0",
                wt: "json"}
      body = conn.get("select", params).body

      begin
        JSON.parse(body)["response"]["numFound"]
      rescue JSON::ParserError => e
        error(message: "could not parse response from #{conn.url_prefix}: #{body} (#{e})")
        0
      end
    end

    def run_for_date(date:)
      super
      # The dates on the files are the previous day, but the indexing
      # happens on the current day. When we verify the current day, we are
      # verifying that the file named for the _previous_ day was produced.
      # This is handled by the derivative class `datestamp_delta`

      @current_date = date
      Derivative::CatalogArchive.derivatives_for_date(date: date).each do |derivative|
        path = derivative.path

        next unless verify_file(path: path)
        verify_index_count(derivative: derivative)
      end
    end
  end
end
