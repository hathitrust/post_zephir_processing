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
      :RIGHTS_DIR,
      :TMPDIR
    ].freeze

    DIR_DATA = {
      zephir_full: {
        location: :CATALOG_PREP,
        pattern: /^zephir_full_(\d{8})_vufind\.json\.gz$/,
        archive: false,
        full: true
      },
      zephir_full_rights: {
        location: :RIGHTS_DIR,
        pattern: /^zephir_full_(\d{8})\.rights$/,
        archive: true,
        full: true
      },
      zephir_update: {
        location: :CATALOG_PREP,
        pattern: /^zephir_upd_(\d{8})\.json\.gz$/,
        archive: false,
        full: false
      },
      zephir_update_rights: {
        location: :RIGHTS_DIR,
        pattern: /^zephir_upd_(\d{8})\.rights$/,
        archive: true,
        full: false
      },
      zephir_update_delete: {
        location: :CATALOG_PREP,
        pattern: /^zephir_upd_(\d{8})_delete\.txt\.gz$/,
        archive: false,
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
      when :RIGHTS_DIR
        ENV["RIGHTS_DIR"] || "/htapps/babel/feed/var/rights"
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

    # Given a name like :zephir_full, return an Array with the associated path,
    # and the archive path if it has one.
    def directories_named(name:)
      [self.class.directory_for(location: DIR_DATA[name][:location])].tap do |dirs|
        if DIR_DATA[name][:archive]
          dirs << File.join(dirs[0], "archive")
        end
      end
    end
  end
end
