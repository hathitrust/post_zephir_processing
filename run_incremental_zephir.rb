# frozen_string_literal: true

require "date"
require "logger"
require_relative "lib/monthly_inventory"

logger = Logger.new($stdout)
HOME = File.expand_path(__dir__).freeze
INCREMENTAL_SCRIPT = File.join(HOME, "run_process_zephir_incremental.sh")
YESTERDAY = Date.today - 1

inventory = PostZephirProcessing::MonthlyInventory.new(logger: logger, date: YESTERDAY)
logger.debug "all existing Zephir updates: #{inventory.inventory}"

if inventory.earliest_missing_date.nil?
  logger.info "no Zephir files to process, exiting"
  exit 0
end

dates = (inventory.earliest_missing_date..YESTERDAY)
logger.debug "Processing Zephir files for: #{dates}"
dates.each do |date|
  date_str = date.strftime("%Y%m%d")
  cmd = "#{INCREMENTAL_SCRIPT} #{date_str}"
  logger.debug "Calling '#{cmd}'"
  # Bail out if `system` returns false or nil
  unless system(cmd)
    logger.error "exitstatus #{$?.exitstatus} from '#{cmd}'"
    exit 1
  end
end
