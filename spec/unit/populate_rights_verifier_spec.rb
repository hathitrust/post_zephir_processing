# frozen_string_literal: true

require "verifier/populate_rights_verifier"

module PostZephirProcessing
  RSpec.describe(PopulateRightsVerifier) do
    around(:each) do |example|
      with_test_environment { example.run }
    end

    let(:test_rights) do
      [
        ["a.123", "ic", "bib", "bibrights", "aa"].join("\t")
      ].join("\n")
    end

    # Temporarily add `htid` to `rights_current` with resonable (and irrelevant) default values.
    def with_fake_rights_entry(htid:)
      namespace, id = htid.split(".", 2)
      Services[:database][:rights_current].where(namespace: namespace, id: id).delete
      Services[:database][:rights_current].insert(
        namespace: namespace,
        id: id,
        attr: 1,
        reason: 1,
        source: 1,
        access_profile: 1
      )
      begin
        yield
      ensure
        Services[:database][:rights_current].where(namespace: namespace, id: id).delete
      end
    end

    describe "#verify_rights_file" do
      context "with HTID in the Rights Database" do
        it "logs no error" do
          with_fake_rights_entry(htid: "a.123") do
            expect_ok(:verify_rights_file, test_rights)
          end
        end
      end

      context "with HTID not in the Rights Database" do
        it "logs an error" do
          expect_not_ok(:verify_rights_file, test_rights, errmsg: /no entry/)
        end
      end
    end
  end
end
