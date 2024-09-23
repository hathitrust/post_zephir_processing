# frozen_string_literal: true

require_relative "dates"

module PostZephirProcessing
  # A class that knows the expected locations of standard Zephir derivative files.
  # `earliest_missing_date` is the main entrypoint when constructing an agenda of Zephir
  # file dates to fetch for processing.
  class Derivatives
    DIR_DATA = {
      zephir_full: {
        name: :zephir_full,
        location: :CATALOG_PREP,
        pattern: /^zephir_full_(\d{8})_vufind\.json\.gz$/,
        archive: false,
        full: true
      },
      zephir_full_rights: {
        name: :zephir_full_rights,
        location: :RIGHTS_DIR,
        pattern: /^zephir_full_(\d{8})\.rights$/,
        archive: true,
        full: true
      },
      zephir_update: {
        name: :zephir_update,
        location: :CATALOG_PREP,
        pattern: /^zephir_upd_(\d{8})\.json\.gz$/,
        archive: false,
        full: false
      },
      zephir_update_rights: {
        name: :zephir_update_rights,
        location: :RIGHTS_DIR,
        pattern: /^zephir_upd_(\d{8})\.rights$/,
        archive: true,
        full: false
      },
      zephir_update_delete: {
        name: :zephir_update_delete,
        location: :CATALOG_PREP,
        pattern: /^zephir_upd_(\d{8})_delete\.txt\.gz$/,
        archive: false,
        full: false
      }
    }.freeze

    attr_reader :dates

    # @param date [Date] the file datestamp date, not the "run date"
    def initialize(date: (Date.today - 1))
      @dates = Dates.new(date: date)
    end

    # The following two methods return a map of location name => array of dates
    # Looks sorta like this:
    # {:zephir_full=>[Date1, Date2, ...], :zephir_full_rights=>[Date1, Date2, ...]}
    def full_derivatives
      @full_derivatives ||= DIR_DATA.select { |key, value| value[:full] }
        .transform_values { |value| directory_inventory(name: value[:name]) }
    end

    def update_derivatives
      @update_derivatives ||= DIR_DATA.select { |key, value| !value[:full] }
        .transform_values { |value| directory_inventory(name: value[:name]) }
    end

    # Iterate over the parts of the inventory separately.
    # Find the earliest (min) date missing (if any) from each.
    # If a date is missing in any one of them then it is a do-over candidate.
    # @return [Date,nil]
    def earliest_missing_date
      earliest = []
      update_derivatives.each do |_dir, inventory_dates|
        delta = dates.all_dates - inventory_dates
        earliest << delta.min if delta.any?
      end
      # Each category in full inventory will have only zero or one entry, that
      # being the most recent last day of the month
      full_derivatives.each do |_dir, inventory_dates|
        if inventory_dates.empty?
          earliest << dates.all_dates.min
        end
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

    def directories_named(name:)
      directories = [
        directory_for(location: DIR_DATA[name][:location])
      ]
      if DIR_DATA[name][:archive]
        directories << File.join(directories[0], "archive")
      end
      directories
    end
  end
end
