# frozen_string_literal: true

require "climate_control"
require "zlib"
require "verifier/post_zephir_verifier"
require "tempfile"

module PostZephirProcessing

  RSpec.describe(PostZephirVerifier) do
    around(:each) do |example|
      Dir.mktmpdir do |tmpdir|
        ClimateControl.modify DATA_ROOT: tmpdir do
          File.open(File.join(tmpdir,"journal.yml"),"w") do |f|
            # minimal yaml -- empty array
            f.puts("--- []")
          end
          example.run
        end
      end
    end

    describe "#verify_deletes_contents" do
      it "accepts a file with a newline and nothing else" do
        Tempfile.create('pzp_test') do |tmpfile|
          gz = Zlib::GzipWriter.new(tmpfile)
          gz.write("\n")
          gz.close
          tmpfile.close
          expect { described_class.new.verify_deletes_contents(path: tmpfile.path) }.not_to raise_exception
        end
      end
      it "accepts a file with one catalog record ID"
      it "accepts a file with multiple catalog record IDs"
      it "rejects a file with a truncated catalog record ID"
      it "rejects a file with a mix of catalog record IDs and whitespace"
      it "rejects a file with a mix of catalog record IDs and gibberish"
    end
  end
end
