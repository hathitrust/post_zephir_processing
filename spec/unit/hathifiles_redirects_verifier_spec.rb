# frozen_string_literal: true

require "verifier/hathifiles_redirects_verifier"
require "zlib"

module PostZephirProcessing
  RSpec.describe(HathifileRedirectsVerifier) do
    let(:test_date) { Date.parse("2023-01-01") }
    let(:verifier) { described_class.new(date: test_date) }
    let(:redirects_file) { verifier.redirects_file(date: test_date) }
    let(:redirects_history_file) { verifier.redirects_history_file(date: test_date) }
    # Including this mess should invalidate either file
    let(:mess) { "oops, messed up a line!" }

    # Clean temp subdir before each test
    before(:each) do
      ["redirects", "redirects_history"].each do |subdir|
        FileUtils.rm_rf(File.join(@tmpdir, subdir))
        FileUtils.mkdir_p(File.join(@tmpdir, subdir))
      end
    end

    around(:each) do |example|
      with_test_environment {
        ClimateControl.modify(
          REDIRECTS_DIR: File.join(@tmpdir, "redirects"),
          REDIRECTS_HISTORY_DIR: File.join(@tmpdir, "redirects_history")
        ) do
          example.run
        end
      }
    end

    # copy fixture to temporary subdir
    def stage_redirects_file
      FileUtils.cp(fixture("redirects/redirects_202301.txt.gz"), ENV["REDIRECTS_DIR"])
    end

    def stage_redirects_history_file
      FileUtils.cp(fixture("redirects/202301.ndj.gz"), ENV["REDIRECTS_HISTORY_DIR"])
    end

    # Intentionally add mess to an otherwise wellformed file to trigger errors
    def malform(file)
      Zlib::GzipWriter.open(file) do |outfile|
        outfile.puts mess
      end
    end

    describe "#initialize" do
      it "sets current_date (attr_reader) by default or by param" do
        expect(described_class.new.current_date).to eq Date.today
        expect(described_class.new(date: test_date).current_date).to eq test_date
      end
    end

    describe "#redirects_file" do
      it "returns path to dated file, based on date param or verifier's default date" do
        expect(verifier.redirects_file).to end_with("redirects_#{test_date.strftime("%Y%m")}.txt.gz")
        expect(verifier.redirects_file(date: Date.today)).to end_with("redirects_#{Date.today.strftime("%Y%m")}.txt.gz")
      end
    end
    describe "#redirects_history_file" do
      it "returns path to dated file, based on date param or verifier's default date" do
        expect(verifier.redirects_history_file).to end_with("#{test_date.strftime("%Y%m")}.ndj.gz")
        expect(verifier.redirects_history_file(date: Date.today)).to end_with("#{Date.today.strftime("%Y%m")}.ndj.gz")
      end
    end

    describe "#verify_redirects" do
      it "will warn twice if both files missing" do
        verifier.verify_redirects(date: test_date)
        expect(verifier.errors.count).to eq 2
        expect(verifier.errors).to include(/not found: #{redirects_file}/)
        expect(verifier.errors).to include(/not found: #{redirects_history_file}/)
      end
      it "will warn once if history file is missing" do
        stage_redirects_file
        verifier.verify_redirects(date: test_date)
        expect(verifier.errors.count).to eq 1
        expect(verifier.errors).to include(/not found: #{redirects_history_file}/)
      end
      it "will warn once if redirects file is missing" do
        stage_redirects_history_file
        verifier.verify_redirects(date: test_date)
        expect(verifier.errors.count).to eq 1
        expect(verifier.errors).to include(/not found: #{redirects_file}/)
      end
      it "will warn if files are there but malformed" do
        stage_redirects_file
        stage_redirects_history_file
        malform(redirects_file)
        malform(redirects_history_file)
        verifier.verify_redirects(date: test_date)
        expect(verifier.errors.count).to eq 2
        expect(verifier.errors).to include(/#{redirects_file}:1 contains malformed line: #{mess}/)
        expect(verifier.errors).to include(/#{redirects_history_file}:1 contains malformed line: #{mess}/)
      end
      it "will not warn if both files are there & valid)" do
        stage_redirects_file
        stage_redirects_history_file
        verifier.verify_redirects(date: test_date)
        expect(verifier.errors).to be_empty
      end
    end

    describe "#verify_redirects_file" do
      it "accepts a well-formed file" do
        stage_redirects_file
        verifier.verify_redirects_file(path: redirects_file)
      end
      it "rejects a malformed file" do
        stage_redirects_file
        malform(redirects_file)
        verifier.verify_redirects_file(path: redirects_file)
        expect(verifier.errors.count).to eq 1
        expect(verifier.errors).to include(/#{redirects_file}:1 contains malformed line: #{mess}/)
      end
    end

    describe "#verify_redirects_history_file" do
      it "accepts a well-formed file" do
        stage_redirects_history_file
        verifier.verify_redirects_history_file(path: redirects_history_file)
      end
      it "rejects a malformed file" do
        stage_redirects_history_file
        malform(redirects_history_file)
        verifier.verify_redirects_history_file(path: redirects_history_file)
        expect(verifier.errors.count).to eq 1
        expect(verifier.errors).to include(/#{redirects_history_file}:1 contains malformed line: #{mess}/)
      end
    end
  end
end
