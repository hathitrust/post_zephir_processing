# frozen_string_literal: true

require "faraday"
require_relative "../verifier"
require_relative "../derivatives"

# Verifies that catalog indexing workflow stage did what it was supposed to.

module PostZephirProcessing
  class CatalogIndexVerifier < Verifier
    def verify_index_count(path:)
      filename = File.basename(path)
      if (m = filename.match(/^zephir_upd_(\d+)\.json\.gz/))
        # in normal operation, we _should_ have indexed this the day after the
        # date listed in the file.
        #
        # could potentially use the journal to determine when we actually
        # indexed it?

        date_of_indexing = Date.parse(m[1]) + 1
        catalog_linecount = gzip_linecount(path: path)
        solr_count = solr_count(date_of_indexing)
      elsif /^zephir_full_\d+_vufind\.json\.gz/.match?(filename)
        catalog_linecount = gzip_linecount(path: path)
        solr_count = solr_nondeleted_records
      else
        raise ArgumentError, "#{path} doesn't seem to be a catalog index file"
      end

      if solr_count < catalog_linecount
        error(message: "#{filename} had #{catalog_linecount} records, but only #{solr_count} had time_of_indexing on #{date_of_indexing} in solr")
      end
    end

    def solr_count(date_of_indexing)
      # get:
      datebegin = date_of_indexing.to_datetime.new_offset(0).strftime("%FT%TZ")
      dateend = (date_of_indexing + 1).to_datetime.new_offset(0).strftime("%FT%TZ")
      solr_result_count("time_of_index:#{datebegin}%20TO%20#{dateend}]")
    end

    def solr_nondeleted_records
      solr_result_count("deleted:false")
    end

    def solr_result_count(filter_query)
      url = "#{ENV["SOLR_URL"]}/select?fq=#{filter_query}&q=*:*&rows=0&wt=json"

      JSON.parse(Faraday.get(url).body)["response"]["numFound"]
    end
  end
end
