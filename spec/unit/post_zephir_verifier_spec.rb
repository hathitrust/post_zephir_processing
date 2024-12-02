# frozen_string_literal: true

require "climate_control"
require "zlib"
require "verifier/post_zephir_verifier"
require "tempfile"
require "logger"

module PostZephirProcessing
  RSpec.describe(PostZephirVerifier) do
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

    # These helpers are based on the ones from
    # #verify_deletes_contents but are more general

    # overwrite with_temp_file if you need to treat temp files differently
    def with_temp_file(contents)
      tempfile = Tempfile.new("tempfile")
      tempfile << contents
      tempfile.close
      yield tempfile.path
    end

    # the expect-methods take a method arg for the method under test,
    # a contents string that's written to a tempfile and passed to the method,
    # and an optional errmsg arg (as a regexp) for specific error checking

    def expect_not_ok(method, contents, errmsg = /ERROR/)
      with_temp_file(contents) do |tmpfile|
        described_class.new.send(method, path: tmpfile)
        expect(@log_str.string).to match(errmsg)
      end
    end

    def expect_ok(method, contents, errmsg = /ERROR/)
      with_temp_file(contents) do |tmpfile|
        described_class.new.send(method, path: tmpfile)
        expect(@log_str.string).not_to match(errmsg)
      end
    end

    describe "#verify_deletes_contents" do
      def with_temp_deletefile(contents)
        Tempfile.create("deletefile") do |tmpfile|
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

      it "accepts a file with a newline and nothing else" do
        contents = "\n"
        expect_ok(contents)
      end

      it "accepts a file with one catalog record ID" do
        contents = <<~EOT
          000123456
        EOT

        expect_ok(contents)
      end

      it "accepts a file with multiple catalog record IDs" do
        contents = <<~EOT
          000001234
          000012345
        EOT

        expect_ok(contents)
      end

      it "accepts a file with a mix of catalog record IDs and blank lines" do
        contents = <<~EOT
          000000001

          212345678
        EOT

        expect_ok(contents)
      end

      it "rejects a file with a truncated catalog record ID" do
        contents = <<~EOT
          12345
        EOT

        expect_not_ok(contents)
      end

      it "rejects a file with a mix of catalog record IDs and whitespace" do
        contents = <<~EOT
          000001234
          000012345

          \t
          000112345
        EOT

        expect_not_ok(contents)
      end

      it "rejects a file with a mix of catalog record IDs and gibberish" do
        contents = <<~EOT
          mashed potatoes
          000001234
        EOT

        expect_not_ok(contents)
      end
    end

    describe "#verify_rights_file_format" do
      it "accepts an empty file" do
        expect_ok(:verify_rights_file_format, "")
      end

      it "accepts a well-formed file" do
        contents = [
          ["a.1", "ic", "bib", "bibrights", "aa"].join("\t"),
          ["a.2", "pd", "bib", "bibrights", "bb"].join("\t"),
          ["a.3", "pdus", "bib", "bibrights", "aa-bb"].join("\t"),
          ["a.4", "und", "bib", "bibrights", "aa-bb"].join("\t")
        ].join("\n")

        expect_ok(:verify_rights_file_format, contents)
      end

      it "rejects a file with malformed volume id" do
        cols_2_to_5 = ["ic", "bib", "bibrights", "aa"].join("\t")
        expect_not_ok(
          :verify_rights_file_format,
          ["", cols_2_to_5].join("\t"),
          /Rights file .+ contains malformed line/
        )
        expect_not_ok(
          :verify_rights_file_format,
          ["x", cols_2_to_5].join("\t"),
          /Rights file .+ contains malformed line/
        )
        expect_not_ok(
          :verify_rights_file_format,
          ["x.", cols_2_to_5].join("\t"),
          /Rights file .+ contains malformed line/
        )
        expect_not_ok(
          :verify_rights_file_format,
          [".x", cols_2_to_5].join("\t"),
          /Rights file .+ contains malformed line/
        )
      end

      it "rejects a file with malformed rights" do
        cols = ["a.1", "ic", "bib", "bibrights", "aa"]
        expect_ok(:verify_rights_file_format, cols.join("\t"))

        cols[1] = ""
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))

        cols[1] = "icus"
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))
      end

      it "rejects a file without bib in col 2" do
        cols = ["a.1", "ic", "bib", "bibrights", "aa"]
        expect_ok(:verify_rights_file_format, cols.join("\t"))

        cols[2] = "BIB"
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))

        cols[2] = ""
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))
      end

      it "rejects a file without bibrights in col 3" do
        cols = ["a.1", "ic", "bib", "bibrights", "aa"]
        expect_ok(:verify_rights_file_format, cols.join("\t"))

        cols[3] = "BIBRIGHTS"
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))

        cols[3] = ""
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))
      end

      it "rejects a file with malformed digitization source" do
        cols = ["a.1", "ic", "bib", "bibrights", "aa"]
        expect_ok(:verify_rights_file_format, cols.join("\t"))

        cols[4] = "aa-aa"
        expect_ok(:verify_rights_file_format, cols.join("\t"))

        cols[4] = "-aa"
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))

        cols[4] = "aa-"
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))

        cols[4] = "AA"
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))

        cols[4] = ""
        expect_not_ok(:verify_rights_file_format, cols.join("\t"))
      end
    end
  end
end
