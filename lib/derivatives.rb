# frozen_string_literal: true

require_relative "dates"

module PostZephirProcessing
  # A class that knows the expected locations of standard Zephir derivative files.
  # `earliest_missing_date` is the main entrypoint when constructing an agenda of Zephir
  # file dates to fetch for processing.
  class Derivatives
    # Location data for the derivatives we care about when constructing our list of missing dates.
    # A file that has multiple locations (rights vs rights_archive) need only exist in one
    # of them.
    # TODO: is it even necessary to consider RIGHTS_DIR any more? Rights files can be expected to
    # be in rights_archive by the time any workflow step that uses this class executes.
    DIR_DATA = {
      zephir_full: {
        locations: [:CATALOG_PREP],
        pattern: /^zephir_full_(\d{8})_vufind\.json\.gz$/,
        full: true
      },
      zephir_full_rights: {
        locations: [:RIGHTS_DIR, :RIGHTS_ARCHIVE],
        pattern: /^zephir_full_(\d{8})\.rights$/,
        full: true
      },
      zephir_update: {
        locations: [:CATALOG_PREP],
        pattern: /^zephir_upd_(\d{8})\.json\.gz$/,
        full: false
      },
      zephir_update_rights: {
        locations: [:RIGHTS_DIR, :RIGHTS_ARCHIVE],
        pattern: /^zephir_upd_(\d{8})\.rights$/,
        full: false
      },
      zephir_update_delete: {
        locations: [:CATALOG_PREP],
        pattern: /^zephir_upd_(\d{8})_delete\.txt\.gz$/,
        full: false
      }
    }.freeze

    attr_reader :dates

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

    # Translate a known file destination as an environment variable key
    # into the path via ENV or a default.
    # @return [String] path to the directory
    def directory_for(location:)
      case location.to_sym
      when :CATALOG_PREP
        ENV["CATALOG_PREP"] || "/htsolr/catalog/prep/"
      when :RIGHTS_DIR
        ENV["RIGHTS_DIR"] || "/htapps/babel/feed/var/rights"
      when :RIGHTS_ARCHIVE
        ENV["RIGHTS_ARCHIVE"] || "/htapps/babel/feed/var/rights/archive"
      end
    end

    # Run regexp against the contents of dir and store matching files
    # that have datestamps in the period of interest.
    # Do the same for the archive directory if it exists.
    # Does not attempt to iterate nonexistent directory.
    # @return [Array<Date>] de-duped and sorted ASC
    def directory_inventory(name:)
      inventory_dates = []
      directories_named(name: name).each do |dir|
        next unless File.directory? dir

        inventory_dates += Dir.children(dir)
          .filter_map { |filename| (m = DIR_DATA[name][:pattern].match(filename)) && Date.parse(m[1]) }
          .select { |date| dates.all_dates.include? date }
      end
      inventory_dates.sort.uniq
    end

    # Given a name like :zephir_full, return an Array with the associated paths
    def directories_named(name:)
      DIR_DATA[name][:locations].map { |loc| directory_for(location: loc) }
    end
  end
end
