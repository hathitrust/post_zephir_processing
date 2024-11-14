# frozen_string_literal: true

require_relative "dates"

module PostZephirProcessing
  # A class that knows the expected locations of standard Zephir derivative files.
  # `earliest_missing_date` is the main entrypoint when constructing an agenda of Zephir
  # file dates to fetch for processing.
  class Derivatives
    STANDARD_LOCATIONS = [
      :CATALOG_ARCHIVE,
      :CATALOG_PREP,
      :RIGHTS_ARCHIVE,
      :TMPDIR
    ].freeze
    # Location data for the derivatives we care about when constructing our list of missing dates.

    DIR_DATA = {
      zephir_full: {
        location: :CATALOG_PREP,
        pattern: /^zephir_full_(\d{8})_vufind\.json\.gz$/,
        full: true
      },
      zephir_full_rights: {
        location: :RIGHTS_ARCHIVE,
        pattern: /^zephir_full_(\d{8})\.rights$/,
        full: true
      },
      zephir_update: {
        location: :CATALOG_PREP,
        pattern: /^zephir_upd_(\d{8})\.json\.gz$/,
        full: false
      },
      zephir_update_rights: {
        location: :RIGHTS_ARCHIVE,
        pattern: /^zephir_upd_(\d{8})\.rights$/,
        full: false
      },
      zephir_update_delete: {
        location: :CATALOG_PREP,
        pattern: /^zephir_upd_(\d{8})_delete\.txt\.gz$/,
        full: false
      }
    }.freeze

    attr_reader :dates

    # Translate a known file destination as an environment variable key
    # into the path via ENV or a default.
    # @return [String] path to the directory
    def self.directory_for(location:)
      case location.to_sym
      when :CATALOG_ARCHIVE
        ENV["CATALOG_ARCHIVE"] || "/htapps/archive/catalog"
      when :CATALOG_PREP
        ENV["CATALOG_PREP"] || "/htsolr/catalog/prep/"
      when :RIGHTS_ARCHIVE
        ENV["RIGHTS_ARCHIVE"] || "/htapps/babel/feed/var/rights/archive"
      when :TMPDIR
        ENV["TMPDIR"] || File.join(ENV["DATA_ROOT"], "work")
      else
        raise "Unknown location #{location}"
      end
    end

    # @param date [Date] the file datestamp date, not the "run date"
    def initialize(date: (Date.today - 1))
      @dates = Dates.new(date: date)
    end

    # @return [Date,nil]
    def earliest_missing_date
      earliest = []
      DIR_DATA.each_pair do |name, data|
        required_dates = data[:full] ? [dates.all_dates.min] : dates.all_dates
        delta = required_dates - directory_inventory(name: name)
        earliest << delta.min if delta.any?
      end
      earliest.min
    end

    private

    # Run regexp against the contents of dir and store matching files
    # that have datestamps in the period of interest.
    # @return [Array<Date>] de-duped and sorted ASC
    def directory_inventory(name:)
      dir = self.class.directory_for(location: DIR_DATA[name][:location])
      Dir.children(dir)
        .filter_map { |filename| (m = DIR_DATA[name][:pattern].match(filename)) && Date.parse(m[1]) }
        .select { |date| dates.all_dates.include? date }
        .sort
        .uniq
    end
  end
end
