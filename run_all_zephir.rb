# frozen_string_literal: true

require "date"
require "fileutils"
require "logger"

require_relative "lib/post_zephir_processing"
require_relative "lib/services"

LOGGER = Logger.new($stdout)


# Get all of the Zephir files in /htsolr/catalog/prep/ (CATALOG_PREP)
# of type zephir_upd_20231206.json.gz
all_zephir_upd = Dir.glob(File.join(Services[:catalog_prep], "zephir_upd_*")).map do |path|
  filename = File.basename(path)
  Date.parse(filename.split("_")[2].split(".").first)
end

LOGGER.debug "All Zephir updates: #{all_zephir_upd}"

dates = [] # Date objects corresponding to the YYYYMMDD on files, not the current date.
# Collect all dates from all_zephir_upd.last.date + 1 day up to yesterday
# Special case: there are no Zephir files at all. Then we just use yesterday
if all_zephir_upd.empty?
  dates = [Date.today - 1]
else
  (all_zephir_upd.last + 1..(Date.today - 1)).each do |date|
    dates << date
  end
end

if dates.none?
  LOGGER.info "no Zephir files to process, exiting"
  exit 0
end

PostZephirProcessing.new(date: Date.today, logger: LOGGER).dump_rights

LOGGER.debug "Zephir updates to fetch: #{dates}"
dates.each do |date|
  pzp = PostZephirProcessing.new(date: date, logger: LOGGER)
  pzp.download_zephir_files
  pzp.run
end



