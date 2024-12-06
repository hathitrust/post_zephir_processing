# frozen_string_literal: true

require "verifier/hathifiles_verifier"

module PostZephirProcessing
  RSpec.describe(HathifilesVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    let(:sample_line) { File.read(fixture("sample_hathifile_line.txt"), encoding: "utf-8") }

    describe "#verify_hathifiles_linecount" do
      context "with a catalog json file with 5 records" do
        let(:verifier) { described_class.new }

        around(:each) do |example|
          contents = "{}\n" * 5
          with_temp_file(contents, gzipped: true) do |catalog_json_gz|
            @catalog_json_gz = catalog_json_gz
            example.run
          end
        end

        it "accepts a hathifile with 5 records" do
          verifier.verify_hathifile_linecount(5, catalog_path: @catalog_json_gz)
          expect(verifier.errors).to be_empty
        end

        it "accepts a hathifile with 10 records" do
          verifier.verify_hathifile_linecount(10, catalog_path: @catalog_json_gz)
          expect(verifier.errors).to be_empty
        end

        it "rejects a hathifile with 4 records" do
          verifier.verify_hathifile_linecount(4, catalog_path: @catalog_json_gz)
          expect(verifier.errors).not_to be_empty
        end

        it "rejects a hathifile with no records" do
          verifier.verify_hathifile_linecount(0, catalog_path: @catalog_json_gz)
          expect(verifier.errors).not_to be_empty
        end
      end
    end

    # the whole enchilada
    describe "#verify_hathifile"

    describe "#verify_hathifile_contents" do
      it "accepts a file with a single real hathifiles entry" do
        expect_ok(:verify_hathifile_contents, sample_line, gzipped: true)
      end

      it "rejects a file where some lines have less than 26 tab-separated columns" do
        contents = sample_line + "mdp.35112100003484\tdeny\n"
        expect_not_ok(:verify_hathifile_contents, contents, errmsg: /.*columns.*/, gzipped: true)
      end
    end

    describe "#catalog_file_for" do
      it "computes a source catalog file based on date - 1" do
        expect(described_class.new.catalog_file_for(Date.parse("2023-01-04")))
          .to eq("#{ENV["CATALOG_ARCHIVE"]}/zephir_upd_20230103.json.gz")
      end

      it "computes a full source catalog file based on date - 1" do
        expect(described_class.new.catalog_file_for(Date.parse("2024-12-01"), full: true))
          .to eq("#{ENV["CATALOG_ARCHIVE"]}/zephir_full_20241130.json.gz")
      end
    end
  end
end
