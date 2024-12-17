# frozen_string_literal: true

require "verifier"

module PostZephirProcessing
  RSpec.describe(Verifier) do
    around(:each) do |example|
      with_test_environment do |tmpdir|
        example.run
      end
    end

    let(:verifier) { described_class.new }
    let(:test_update_file) { "zephir_upd_20241202.json.gz" }
    let(:test_update_fixture) { fixture(File.join("catalog_archive", test_update_file)) }
    let(:test_update_linecount) { 3 }

    describe ".new" do
      it "creates a Verifier" do
        expect(verifier).to be_an_instance_of(Verifier)
      end

      context "with no Journal file" do
        it "raises StandardError" do
          FileUtils.rm(File.join(@tmpdir, "journal.yml"))
          expect { verifier }.to raise_error(StandardError)
        end
      end
    end

    describe ".run" do
      it "runs to completion" do
        verifier.run
      end
    end

    describe "#verify_file" do
      # Note: since the tests currently run as root, no way to test unreadable file

      it "starts with no errors" do
        expect(verifier.errors).to be_empty
      end

      context "with readable file" do
        it "does not report an error" do
          tmpfile = File.join(@tmpdir, "tmpfile.txt")
          File.open(tmpfile, "w") { |f| f.puts "blah" }
          verifier.verify_file(path: tmpfile)
          expect(verifier.errors).to be_empty
        end
      end

      context "with nonexistent file" do
        it "reports an error" do
          verifier.errors.count
          tmpfile = File.join(@tmpdir, "no_such_tmpfile.txt")
          verifier.verify_file(path: tmpfile)
          expect(verifier.errors).not_to be_empty
        end
      end
    end

    describe "#gzip_linecount" do
      it "returns the correct number of lines" do
        expect(verifier.gzip_linecount(path: test_update_fixture)).to eq(test_update_linecount)
      end
    end

    describe "#verify_parseable_ndj" do
      it "returns `true` and no errors if a .ndj file contains only parseable lines" do
        content = "{}\n[]"
        expect_ok(:verify_parseable_ndj, content, gzipped: true, check_return: true)
      end
      it "warns and returns `false` if it sees an unparseable line" do
        content = "oops\n{}\n[]\n"
        expect_not_ok(:verify_parseable_ndj, content, errmsg: /unparseable JSON/, gzipped: true, check_return: true)
      end
    end
  end
end
