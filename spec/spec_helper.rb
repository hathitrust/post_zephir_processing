# frozen_string_literal: true

require "climate_control"
require "dotenv"
require "logger"
require "tmpdir"
require "tempfile"
require "simplecov"
require "simplecov-lcov"
require "webmock/rspec"
require "zlib"

require "dates"
require "journal"
require "verifier"

require "support/solr_mock"
require "support/hathifile_database"

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

# squelch log output from tests
PostZephirProcessing::Services.register(:logger) {
  Logger.new(File.open(File::NULL, "w"), level: Logger::DEBUG)
}

def test_journal
  <<~TEST_YAML
    ---
    - '20500101'
    - '20500102'
  TEST_YAML
end

def test_journal_dates
  [Date.new(2050, 1, 1), Date.new(2050, 1, 2)]
end

# Note potential pitfall:
# Setting ENV["TMPDIR"] has an effect on Ruby's choice of temporary directory locations.
# See https://github.com/ruby/ruby/blob/f4476f0d07c781c906ed1353d8e1be5a7314d6e7/lib/tmpdir.rb#L130
# So if you see mktmpdir yielding a location in spec/fixtures then it's likely
# TMPDIR has been defined, maybe in an `around` block, before the call to `with_test_environment`.
# Currently it is not happening but it can when noodling around with test setups.
# It's not a critical problem, but might nudge us in the direction of moving away from using
# TMPDIR in the PZP internals.
# Could also try wrapping the mktmpdir in another Climate Control layer.
def with_test_environment
  Dir.mktmpdir do |tmpdir|
    ClimateControl.modify(
      DATA_ROOT: tmpdir,
      TMPDIR: tmpdir
    ) do
      # Maybe we don't need to yield `tmpdir` since we're also assigning it to an
      # instance variable. Leaving it for now in case the ivar approach leads to funny business.
      @tmpdir = tmpdir
      yield tmpdir
    end
  end
end

def write_gzipped(tmpfile, contents)
  gz = Zlib::GzipWriter.new(tmpfile)
  gz.write(contents)
  gz.close
end

def with_temp_file(contents, gzipped: false)
  Tempfile.create("tempfile") do |tmpfile|
    if gzipped
      write_gzipped(tmpfile, contents)
    else
      tmpfile.write(contents)
    end
    tmpfile.close
    yield tmpfile.path
  end
end

def expect_not_ok(method, contents, errmsg: /.*/, gzipped: false, check_return: false)
  with_temp_file(contents, gzipped: gzipped) do |tmpfile|
    verifier = described_class.new
    result = verifier.send(method, path: tmpfile)
    expect(verifier.errors).to include(errmsg)
    if check_return
      expect(result).to be false
    end
  end
end

def expect_ok(method, contents, gzipped: false, check_return: false)
  with_temp_file(contents, gzipped: gzipped) do |tmpfile|
    verifier = described_class.new
    result = verifier.send(method, path: tmpfile)
    expect(verifier.errors).to be_empty
    if check_return
      expect(result).to be true
    end
  end
end

# Returns the full path to the given fixture file.
#
# @param file [String]
def fixture(file)
  File.join(File.dirname(__FILE__), "fixtures", file)
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
