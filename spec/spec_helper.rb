# frozen_string_literal: true

require "dotenv"
require "logger"
require "simplecov"
require "simplecov-lcov"

Dotenv.load(File.join(ENV.fetch("ROOTDIR"), "config", "env"))

SimpleCov.add_filter "spec"

SimpleCov::Formatter::LcovFormatter.config do |c|
  c.report_with_single_file = true
  c.single_report_path = "coverage/lcov.info"
end
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::LcovFormatter
])
SimpleCov.start

require_relative "../lib/dates"
require_relative "../lib/derivatives"
require_relative "../lib/journal"

ENV["POST_ZEPHIR_LOGGER_LEVEL"] = Logger::WARN.to_s

def catalog_prep_dir
  File.join(ENV["SPEC_TMPDIR"], "catalog_prep")
end

def rights_dir
  File.join(ENV["SPEC_TMPDIR"], "rights")
end

def rights_archive_dir
  File.join(ENV["SPEC_TMPDIR"], "rights", "archive")
end

# Set the all-important SPEC_TMPDIR and derivative env vars,
# and populate test dir with the appropriate directories.
def setup_test_dirs(parent_dir:)
  ENV["SPEC_TMPDIR"] = parent_dir
  ENV["CATALOG_PREP"] = catalog_prep_dir
  ENV["RIGHTS_DIR"] = rights_dir
  [catalog_prep_dir, rights_dir, rights_archive_dir].each do |loc|
    Dir.mkdir loc
  end
end

def full_file_for_date(date:)
  File.join(catalog_prep_dir, "zephir_full_#{date.strftime("%Y%m%d")}_vufind.json.gz")
end

def full_rights_file_for_date(date:, archive: true)
  File.join(
    archive ? rights_archive_dir : rights_dir,
    "zephir_full_#{date.strftime("%Y%m%d")}.rights"
  )
end

def update_file_for_date(date:)
  File.join(catalog_prep_dir, "zephir_upd_#{date.strftime("%Y%m%d")}.json.gz")
end

def delete_file_for_date(date:)
  File.join(catalog_prep_dir, "zephir_upd_#{date.strftime("%Y%m%d")}_delete.txt.gz")
end

def update_rights_file_for_date(date:, archive: true)
  File.join(
    archive ? rights_archive_dir : rights_dir,
    "zephir_upd_#{date.strftime("%Y%m%d")}.rights"
  )
end

# @param date [Date] determines the month and year for the file datestamps
def setup_test_files(date:)
  start_date = Date.new(date.year, date.month - 1, -1)
  `touch #{full_file_for_date(date: start_date)}`
  `touch #{full_rights_file_for_date(date: start_date)}`
  end_date = Date.new(date.year, date.month, -2)
  (start_date..end_date).each do |d|
    `touch #{update_file_for_date(date: d)}`
    `touch #{delete_file_for_date(date: d)}`
    `touch #{update_rights_file_for_date(date: d)}`
  end
end

# The following RSpec boilerplate tends to recur across HathiTrust Ruby test suites.
RSpec.configure do |config|
  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    #     be_bigger_than(2).and_smaller_than(4).description
    #     # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #     # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # This option will default to `:apply_to_host_groups` in RSpec 4 (and will
  # have no way to turn it off -- the option exists only for backwards
  # compatibility in RSpec 3). It causes shared context metadata to be
  # inherited by the metadata hash of host groups and examples, rather than
  # triggering implicit auto-inclusion in groups with matching metadata.
  config.shared_context_metadata_behavior = :apply_to_host_groups
end
