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
      context "with readable file" do
        it "does not report an error" do
          errors_before = verifier.errors.count
          tmpfile = File.join(@tmpdir, "tmpfile.txt")
          File.open(tmpfile, "w") { |f| f.puts "blah" }
          verifier.verify_file(path: tmpfile)
          expect(verifier.errors.count).to eq(errors_before)
        end
      end

      context "with nonexistent file" do
        it "reports an error" do
          errors_before = verifier.errors.count
          tmpfile = File.join(@tmpdir, "no_such_tmpfile.txt")
          verifier.verify_file(path: tmpfile)
          expect(verifier.errors.count).to be > errors_before
        end
      end
    end

    describe "#gzip_linecount" do
      it "returns the correct number of lines" do
        expect(verifier.gzip_linecount(path: TEST_UPDATE_FIXTURE)).to eq(TEST_UPDATE_LINECOUNT)
      end
    end
  end
end
