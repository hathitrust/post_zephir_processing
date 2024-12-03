# frozen_string_literal: true

require "climate_control"
require "zlib"
require "verifier/post_zephir_verifier"
require "tempfile"
require "logger"

module PostZephirProcessing
  RSpec.describe(HathifilesVerifier) do
    def with_temp_hathifile(contents)
      Tempfile.create("hathifile") do |tmpfile|
        gz = Zlib::GzipWriter.new(tmpfile)
        gz.write(contents)
        gz.close
        yield tmpfile.path
      end
    end

    def expect_not_ok(contents)
      with_temp_deletefile(contents) do |tmpfile|
        described_class.new.verify_deletes_contents(path: tmpfile)
        expect(@log_str.string).to match(/ERROR.*deletefile.*expecting catalog record ID/)
      end
    end

    def expect_ok(contents)
      with_temp_deletefile(contents) do |tmpfile|
        described_class.new.verify_deletes_contents(path: tmpfile)
        expect(@log_str.string).not_to match(/ERROR/)
      end
    end

    around(:each) do |example|
      @log_str = StringIO.new
      old_logger = Services.logger
      Services.register(:logger) { Logger.new(@log_str, level: Logger::DEBUG) }
      example.run
      Services.register(:logger) { old_logger }
    end

    around(:each) do |example|
      Dir.mktmpdir do |tmpdir|
        ClimateControl.modify DATA_ROOT: tmpdir do
          File.open(File.join(tmpdir, "journal.yml"), "w") do |f|
            # minimal yaml -- empty array
            f.puts("--- []")
          end
          example.run
        end
      end
    end
  end
end
