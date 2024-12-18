# frozen_string_literal: true

require "verifier/post_zephir_verifier"
require "zinzout"

module PostZephirProcessing
  RSpec.describe(PostZephirVerifier) do
    around(:each) do |example|
      ClimateControl.modify(
        CATALOG_ARCHIVE: fixture("catalog_archive"),
        ZEPHIR_DATA: fixture("zephir_data")
      ) do
        with_test_environment { example.run }
      end
    end

    let(:well_formed_rights_file_content) do
      [
        ["a.1", "ic", "bib", "bibrights", "aa"].join("\t"),
        ["a.2", "pd", "bib", "bibrights", "bb"].join("\t"),
        ["a.3", "pdus", "bib", "bibrights", "aa-bb"].join("\t"),
        ["a.4", "und", "bib", "bibrights", "aa-bb"].join("\t")
      ].join("\n")
    end

    describe "#run_for_date" do
      context "last day of month" do
        test_date = Date.parse("2024-11-30")
        it "runs" do
          described_class.new.run_for_date(date: test_date)
        end
      end

      context "non-last day of month" do
        test_date = Date.parse("2024-12-01")
        it "runs" do
          described_class.new.run_for_date(date: test_date)
        end
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

    describe "#verify_catalog_archive" do
      let(:verifier) { described_class.new }
      let(:test_date) { Date.parse("2024-11-30") }
      it "requires input file to have same line count as output file" do
        # We have fixtures with matching line counts for test_date,
        # so expect no warnings
        verifier.verify_catalog_archive(date: test_date)
        expect(verifier.errors).to be_empty
      end

      it "warns if there is a input/output line count mismatch" do
        # Make a temporary ht_bib_export with just 1 line to trigger error
        ClimateControl.modify(ZEPHIR_DATA: "/tmp/test/zephir_data") do
          FileUtils.mkdir_p(ENV["ZEPHIR_DATA"])
          Zinzout.zout(File.join(ENV["ZEPHIR_DATA"], "ht_bib_export_full_2024-11-30.json.gz")) do |gz|
            gz.puts "{ \"this file\": \"too short\" }"
          end
          # The other unmodified fixtures in CATALOG_ARCHIVE should
          # no longer have matching line counts, so expect a warning
          verifier.verify_catalog_archive(date: test_date)
          expect(verifier.errors.count).to eq 1
          expect(verifier.errors).to include(/output line count .+ != input line count/)
        end
      end
    end

    describe "#verify_catalog_prep" do
      test_date = Date.parse("2024-11-30")
      context "with all the expected files" do
        it "reports no errors" do
          # Create and test upd, full, and deletes in @tmpdir/catalog_prep
          ClimateControl.modify(CATALOG_PREP: @tmpdir) do
            FileUtils.cp(fixture(File.join("catalog_archive", "zephir_full_20241130_vufind.json.gz")), @tmpdir)
            FileUtils.cp(fixture(File.join("catalog_archive", "zephir_upd_20241130.json.gz")), @tmpdir)
            FileUtils.cp(fixture(File.join("catalog_prep", "zephir_upd_20241130_delete.txt.gz")), @tmpdir)
            verifier = described_class.new
            verifier.verify_catalog_prep(date: test_date)
            expect(verifier.errors.count).to eq 0
          end
        end
      end

      context "without any of the expected files" do
        it "reports an error for each of the three missing files" do
          ClimateControl.modify(CATALOG_PREP: @tmpdir) do
            verifier = described_class.new
            verifier.verify_catalog_prep(date: test_date)
            expect(verifier.errors.count).to eq 3
          end
        end
      end
    end

    describe "#verify_dollar_dup" do
      test_date = Date.parse("2024-12-01")
      context "with empty file" do
        it "reports no errors" do
          ClimateControl.modify(TMPDIR: @tmpdir) do
            dollar_dup_path = File.join(@tmpdir, "vufind_incremental_2024-12-01_dollar_dup.txt.gz")
            Zinzout.zout(dollar_dup_path) { |output_gz| }
            verifier = described_class.new
            verifier.verify_dollar_dup(date: test_date)
            expect(verifier.errors).to eq []
          end
        end
      end

      context "with nonempty file" do
        it "reports one `spurious dollar_dup lines` error" do
          ClimateControl.modify(TMPDIR: @tmpdir) do
            dollar_dup_path = File.join(@tmpdir, "vufind_incremental_2024-12-01_dollar_dup.txt.gz")
            Zinzout.zout(dollar_dup_path) do |output_gz|
              output_gz.puts <<~GZ
                uc1.b275234
                uc1.b85271
                uc1.b312920
                uc1.b257214
                uc1.b316327
                uc1.b23918
                uc1.b95355
                uc1.b183819
                uc1.b197217
              GZ
            end
            verifier = described_class.new
            verifier.verify_dollar_dup(date: test_date)
            expect(verifier.errors.count).to eq 1
            expect(verifier.errors).to include(/spurious dollar_dup lines/)
          end
        end
      end

      context "with missing file" do
        it "reports one `not found` error" do
          ClimateControl.modify(TMPDIR: @tmpdir) do
            verifier = described_class.new
            verifier.verify_dollar_dup(date: test_date)
            expect(verifier.errors.count).to eq 1
            expect(verifier.errors).to include(/^not found/)
          end
        end
      end
    end

    describe "#verify_ingest_bibrecords" do
      context "last day of month" do
        test_date = Date.parse("2024-11-30")
        context "with expected groove_full and zephir_ingested_items files" do
          it "reports no errors" do
            ClimateControl.modify(INGEST_BIBRECORDS: @tmpdir) do
              FileUtils.touch(File.join(@tmpdir, "groove_full.tsv.gz"))
              FileUtils.touch(File.join(@tmpdir, "zephir_ingested_items.txt.gz"))
              verifier = described_class.new
              verifier.verify_ingest_bibrecords(date: test_date)
              expect(verifier.errors.count).to eq 0
            end
          end
        end

        context "missing zephir_ingested_items" do
          it "reports one `not found` error" do
            ClimateControl.modify(INGEST_BIBRECORDS: @tmpdir) do
              FileUtils.touch(File.join(@tmpdir, "groove_full.tsv.gz"))
              verifier = described_class.new
              verifier.verify_ingest_bibrecords(date: test_date)
              expect(verifier.errors.count).to eq 1
              expect(verifier.errors).to include(/^not found/)
            end
          end
        end

        context "missing groove_full" do
          it "reports one `not found` error" do
            ClimateControl.modify(INGEST_BIBRECORDS: @tmpdir) do
              FileUtils.touch(File.join(@tmpdir, "zephir_ingested_items.txt.gz"))
              verifier = described_class.new
              verifier.verify_ingest_bibrecords(date: test_date)
              expect(verifier.errors.count).to eq 1
              expect(verifier.errors).to include(/^not found/)
            end
          end
        end
      end

      context "non-last day of month" do
        test_date = Date.parse("2024-12-01")
        it "reports no errors" do
          verifier = described_class.new
          verifier.verify_ingest_bibrecords(date: test_date)
          expect(verifier.errors.count).to eq 0
        end
      end
    end

    describe "#verify_rights" do
      context "last day of month" do
        test_date = Date.parse("2024-11-30")
        context "with full and update rights files" do
          it "reports no errors" do
            ClimateControl.modify(RIGHTS_ARCHIVE: @tmpdir) do
              verifier = described_class.new
              upd_rights_file = "zephir_upd_YYYYMMDD.rights".gsub("YYYYMMDD", test_date.strftime("%Y%m%d"))
              upd_rights_path = File.join(@tmpdir, upd_rights_file)
              File.write(upd_rights_path, well_formed_rights_file_content)
              full_rights_file = "zephir_full_YYYYMMDD.rights".gsub("YYYYMMDD", test_date.strftime("%Y%m%d"))
              full_rights_path = File.join(@tmpdir, full_rights_file)
              File.write(full_rights_path, well_formed_rights_file_content)
              verifier.verify_rights(date: test_date)
              expect(verifier.errors.count).to eq 0
            end
          end
        end

        context "with no rights files" do
          it "reports two `not found` errors" do
            ClimateControl.modify(RIGHTS_ARCHIVE: @tmpdir) do
              verifier = described_class.new
              verifier.verify_rights(date: test_date)
              expect(verifier.errors.count).to eq 2
              verifier.errors.each do |err|
                expect(err).to include(/^not found/)
              end
            end
          end
        end
      end

      context "non-last day of month" do
        test_date = Date.parse("2024-12-01")
        context "with update rights file" do
          it "reports no errors" do
            ClimateControl.modify(RIGHTS_ARCHIVE: @tmpdir) do
              verifier = described_class.new
              rights_file = "zephir_upd_YYYYMMDD.rights".gsub("YYYYMMDD", test_date.strftime("%Y%m%d"))
              rights_path = File.join(@tmpdir, rights_file)
              File.write(rights_path, well_formed_rights_file_content)
              verifier.verify_rights(date: test_date)
              expect(verifier.errors.count).to eq 0
            end
          end
        end

        context "missing update rights file" do
          it "reports one `not found` error" do
            ClimateControl.modify(RIGHTS_ARCHIVE: @tmpdir) do
              verifier = described_class.new
              verifier.verify_rights(date: test_date)
              expect(verifier.errors.count).to eq 1
              expect(verifier.errors).to include(/^not found/)
            end
          end
        end
      end
    end

    describe "#verify_rights_file_format" do
      let(:rights_cols) { ["a.1", "ic", "bib", "bibrights", "aa"] }

      it "accepts an empty file" do
        expect_ok(:verify_rights_file_format, "")
      end

      it "accepts a well-formed file" do
        expect_ok(:verify_rights_file_format, well_formed_rights_file_content)
      end

      it "accepts a well-formed line" do
        expect_ok(:verify_rights_file_format, rights_cols.join("\t"))
      end

      volids_not_ok = ["", "x", "x.", ".x", "X.X"]
      volids_not_ok.each do |bad_volume_id|
        it "rejects a file with malformed volume id" do
          rights_cols[0] = bad_volume_id

          expect_not_ok(
            :verify_rights_file_format,
            rights_cols.join("\t"),
            errmsg: /invalid column id/
          )
        end
      end

      it "rejects a file with no rights" do
        rights_cols[1] = ""
        expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column rights/)
      end

      it "rejects a file with unexpected (icus) rights" do
        rights_cols[1] = "icus"
        expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column rights/)
      end

      it "rejects a file without 'bib' (lowercase) in col 2" do
        rights_cols[2] = "BIB"
        expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column bib/)
      end

      it "rejects a file with no reason in col 2" do
        rights_cols[2] = ""
        expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column bib/)
      end

      it "rejects a file without 'bibrights' (lowercase) in col 3" do
        rights_cols[3] = "BIBRIGHTS"
        expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column bibrights/)
      end

      it "rejects a file with no user in col 3" do
        rights_cols[3] = ""
        expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column bibrights/)
      end

      it "accepts a file with OK digitization source" do
        rights_cols[4] = "aa-aa"
        expect_ok(:verify_rights_file_format, rights_cols.join("\t"))
      end

      not_ok_dig_sources = ["", "-aa", "aa-", "AA"]
      not_ok_dig_sources.each do |bad_dig_source|
        it "rejects a file with malformed digitization source (#{bad_dig_source})" do
          rights_cols[4] = bad_dig_source

          expect_not_ok(:verify_rights_file_format, rights_cols.join("\t"), errmsg: /invalid column digitization_source/)
        end
      end
    end
  end
end
