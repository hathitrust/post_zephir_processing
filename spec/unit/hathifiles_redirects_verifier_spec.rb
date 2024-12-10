# frozen_string_literal: true

require "verifier/hathifiles_redirects_verifier"

module PostZephirProcessing
  RSpec.describe(HathifileRedirectsVerifier) do
    let(:verifier) { described_class.new }
    let(:test_date) { Date.parse("2023-01-01") }
    let(:redirects_file) { verifier.redirects_file(date: test_date) }
    let(:redirects_history_file) { verifier.redirects_history_file(date: test_date) }
    let(:mess) { "oops, messed up a line!" }

    # Clean dir before each test
    before(:each) do
      [ENV["REDIRECTS_DIR"], ENV["REDIRECTS_HISTORY_DIR"]].each do |dir|
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(dir)
      end
    end

    around(:each) do |example|
      with_test_environment { example.run }
    end

    def stage_redirects_file
      FileUtils.cp(fixture("redirects/redirects_202301.txt.gz"), ENV["REDIRECTS_DIR"])
    end

    def stage_redirects_history_file
      FileUtils.cp(fixture("redirects/202301.ndj.gz"), ENV["REDIRECTS_HISTORY_DIR"])
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
      it "will not warn if both files are there" do
        stage_redirects_file
        stage_redirects_history_file
        verifier.verify_redirects(date: test_date)
        expect(verifier.errors).to be_empty
      end
    end

    describe "#verify_redirects_file" do
      it "accepts a well-formed file" do
        stage_redirects_file
        verifier.current_date = test_date
        verifier.verify_redirects_file(path: redirects_file)
      end
      it "rejects a malformed file" do
        stage_redirects_file
        # intentionally mess up the staged file
        Zinzout.zout(redirects_file) do |outfile|
          outfile.puts mess
        end
        verifier.current_date = test_date
        verifier.verify_redirects_file(path: redirects_file)
        expect(verifier.errors.count).to eq 1
        expect(verifier.errors).to include(/#{redirects_file} contains malformed line: #{mess}/)
      end
    end

    describe "#verify_redirects_history_file" do
      it "accepts a well-formed file" do
        stage_redirects_history_file
        verifier.current_date = test_date
        verifier.verify_redirects_history_file(path: redirects_history_file)
      end
      it "rejects a malformed file" do
        stage_redirects_history_file
        # intentionally mess up the staged file
        Zinzout.zout(redirects_history_file) do |outfile|
          outfile.puts mess
        end
        verifier.current_date = test_date
        verifier.verify_redirects_history_file(path: redirects_history_file)
        expect(verifier.errors.count).to eq 1
        expect(verifier.errors).to include(/#{redirects_history_file} contains malformed line: #{mess}/)
      end
    end
  end
end
