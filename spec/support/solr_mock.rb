RSpec.shared_context "with solr mocking" do
  let(:solr_url) { "http://solr-sdr-catalog:9033/solr/catalog" }

  def stub_solr_count(fq:, result_count:)
    url = "#{solr_url}/select?fq=#{URI.encode_www_form_component(fq)}&q=*:*&rows=0&wt=json"

    result = {
      "responseHeader" => {
        "status" => 0,
        "QTime" => 0,
        "params" => {
          "q" => "*=>*",
          "fq" => fq,
          "rows" => "0",
          "wt" => "json"
        }
      },
      "response" => {"numFound" => result_count, "start" => 0, "docs" => []}
    }.to_json

    WebMock::API.stub_request(:get, url)
      .with(basic_auth: ["solr", "SolrRocks"])
      .to_return(body: result, headers: {"Content-Type" => "application/json"})
  end

  def stub_catalog_record_count(result_count)
    stub_solr_count(fq: "deleted:false", result_count: result_count)
  end

  def stub_catalog_timerange(datebegin, result_count)
    stub_solr_count(fq: "time_of_index:[#{datebegin} TO NOW] AND deleted:false", result_count: result_count)
  end
end
