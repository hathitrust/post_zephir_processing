# frozen_string_literal: true

require "date"
require "logger"

module PostZephirProcessing
  class MonthlyInventory
    UPDATE_REGEXP = /^zephir_upd_(\d{8})\.json\.gz$/
    DELETE_REGEXP = /^zephir_upd_(\d{8})_delete\.txt\.gz$/
    RIGHTS_REGEXP = /^zephir_upd_(\d{8})\.rights$/
    attr_reader :date, :logger, :inventory

    # @param logger [Logger] defaults to STDOUT
    # @param date [Date] the file datestamp date, not the "run date"
    def initialize(logger: nil, date: (Date.today - 1))
      @logger = logger || Logger.new($stdout, level: ENV.fetch("POST_ZEPHIR_LOGGER_LEVEL", Logger::INFO).to_i)
      @date = date
      @logger.info("MonthlyInventory using date #{@date}")
      # TODO: these should go in .env/Canister
      @catalog_prep_dir = ENV["CATALOG_PREP"] || "/htsolr/catalog/prep/"
      @rights_dir = ENV["RIGHTS_DIR"] || "/htapps/babel/feed/var/rights"
      @rights_archive_dir = File.join(@rights_dir, "archive")
      @ingest_bibrecords_dir = ENV["INGEST_BIBRECORDS"] || "/htapps/babel/feed/var/bibrecords"
      @ingest_bibrecords_archive_dir = File.join(@ingest_bibrecords_dir, "archive")
      @inventory = {
        zephir_update_files: zephir_update_files,
        zephir_delete_files: zephir_delete_files,
        zephir_rights_files: zephir_rights_files,
      }
    end

    # zephir_upd_YYYYMMDD.json.gz files for the current month.
    # @return [Array<Date>] sorted ASC
    def zephir_update_files
      directory_inventory(directory: @catalog_prep_dir, regexp: UPDATE_REGEXP)
    end

    # zephir_upd_YYYYMMDD_delete.txt.gz files for the current month.
    # @return [Array<Date>] sorted ASC
    def zephir_delete_files
      directory_inventory(directory: @catalog_prep_dir, regexp: DELETE_REGEXP)
    end

    # zephir_upd_YYYYMMDD.rights files for the current month.
    # @return [Array<Date>] sorted ASC
    def zephir_rights_files
      directory_inventory(directory: @rights_dir, archive_directory: @rights_archive_dir, regexp: RIGHTS_REGEXP)
    end

    # Iterate over the parts of the inventory separately.
    # Find the earliest (min) date missing (if any) from each.
    # If a date is missing in any one of them then it is a do-over candidate.
    # @return [Date,nil]
    def earliest_missing_date
      earliest = []
      inventory.each do |_category, dates|
        delta = all_dates - dates
        earliest << delta.min unless delta.empty?
      end
      earliest.min
    end

    # Beginning of month to "present"
    # @return [Array<Date>] sorted ASC
    def all_dates
      @all_dates ||= (Date.new(date.year, date.month, 1)..date).to_a.sort
    end

    private

    # Run regexp against the contents of dir and store matching files
    # that have datestamps in the month of interest.
    # Do the same for the archive directory if it is supplied.
    # Does not attempt to iterate nonexistent directory.
    # @return [Array<Date>] sorted ASC
    def directory_inventory(directory:, regexp:, archive_directory: nil)
      dates = []
      [directory, archive_directory].compact.uniq.each do |dir|
        next unless File.directory? dir

        dates += Dir.children(dir)
          .filter_map { |filename| (m = regexp.match(filename)) && Date.parse(m[1]) }
          .select { |file_date| file_date.month == date.month && file_date.year == date.year }
      end
      dates.sort.uniq
    end
  end
end
