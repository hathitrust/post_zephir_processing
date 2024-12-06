# frozen_string_literal: true

require "verifier/post_zephir_verifier"

module PostZephirProcessing
  RSpec.describe(PostZephirVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    # These helpers are based on the ones from
    # #verify_deletes_contents but are more general

    # the expect-methods take a method arg for the method under test,
    # a contents string that's written to a tempfile and passed to the method,
    # and an optional errmsg arg (as a regexp) for specific error checking

    def expect_not_ok(method, contents, errmsg: /.*/, gzipped: false)
      with_temp_file(contents, gzipped: gzipped) do |tmpfile|
        verifier = described_class.new
        verifier.send(method, path: tmpfile)
        expect(verifier.errors).to include(errmsg)
      end
    end

    def expect_ok(method, contents, gzipped: false)
      with_temp_file(contents, gzipped: gzipped) do |tmpfile|
        verifier = described_class.new
        verifier.send(method, path: tmpfile)
        expect(verifier.errors).to be_empty
      end
    end

    describe "#verify_deletes_contents" do
      def expect_deletefile_error(contents)
        expect_not_ok(:verify_deletes_contents,
          contents,
          gzipped: true,
          errmsg: /.*tempfile.*expecting catalog record ID/)
      end

      def expect_deletefile_ok(contents)
        expect_ok(:verify_deletes_contents, contents, gzipped: true)
      end

      it "accepts a file with a newline and nothing else" do
        contents = "\n"
        expect_deletefile_ok(contents)
      end

      it "accepts a file with one catalog record ID" do
        contents = <<~EOT
          000123456
        EOT

        expect_deletefile_ok(contents)
      end

      it "accepts a file with multiple catalog record IDs" do
        contents = <<~EOT
          000001234
          000012345
        EOT

        expect_deletefile_ok(contents)
      end

      it "accepts a file with a mix of catalog record IDs and blank lines" do
        contents = <<~EOT
          000000001

          212345678
        EOT

        expect_deletefile_ok(contents)
      end

      it "rejects a file with a truncated catalog record ID" do
        contents = <<~EOT
          12345
        EOT

        expect_deletefile_error(contents)
      end

      it "rejects a file with a mix of catalog record IDs and whitespace" do
        contents = <<~EOT
          000001234
          000012345

          \t
          000112345
        EOT

        expect_deletefile_error(contents)
      end

      it "rejects a file with a mix of catalog record IDs and gibberish" do
        contents = <<~EOT
          mashed potatoes
          000001234
        EOT

        expect_deletefile_error(contents)
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

      volids_not_ok = ["", "x", "x.", ".x", "X.X"]
      line_end = ["ic", "bib", "bibrights", "aa"].join("\t")
      volids_not_ok.each do |volid|
        it "rejects a file with malformed volume id" do
          expect_not_ok(
            :verify_rights_file_format,
            [volid, line_end].join("\t"),
            errmsg: /Rights file .+ contains malformed line/
          )
        end
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

      it "accepts a file with OK digitization source" do
        cols = ["a.1", "ic", "bib", "bibrights", "aa"]
        expect_ok(:verify_rights_file_format, cols.join("\t"))

        cols[4] = "aa-aa"
        expect_ok(:verify_rights_file_format, cols.join("\t"))
      end

      not_ok_dig_src = ["", "-aa", "aa-", "AA"]
      line_start = ["a.1", "ic", "bib", "bibrights"].join("\t")
      not_ok_dig_src.each do |dig_src|
        it "rejects a file with malformed digitization source (#{dig_src})" do
          expect_not_ok(:verify_rights_file_format, [line_start, dig_src].join("\t"))
        end
      end
    end
  end
end
