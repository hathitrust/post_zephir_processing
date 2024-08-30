#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "logger"
require_relative "../lib/monthly_inventory"

def run_system_command(command)
  LOGGER.info command
  system(command, exception: true)
end

LOGGER = Logger.new($stdout)
HOME = File.expand_path(File.join(__dir__, "..")).freeze
FULL_SCRIPT = File.join(HOME, "run_zephir_full_monthly.sh")
INCREMENTAL_SCRIPT = File.join(HOME, "run_process_zephir_incremental.sh")
YESTERDAY = Date.today - 1

inventory = PostZephirProcessing::MonthlyInventory.new(logger: LOGGER, date: YESTERDAY)
LOGGER.info "all existing Zephir full files: #{inventory.full_inventory}"
LOGGER.info "all existing Zephir updates: #{inventory.update_inventory}"

if inventory.earliest_missing_date.nil?
  LOGGER.info "no Zephir files to process, exiting"
  exit 0
end

dates = (inventory.earliest_missing_date..YESTERDAY)
LOGGER.info "Processing Zephir files from #{dates}"
dates.each do |date|
  date_str = date.strftime("%Y%m%d")
  if date.last_of_month?
    run_system_command "#{FULL_SCRIPT} #{date_str}"
  end
  run_system_command "#{INCREMENTAL_SCRIPT} #{date_str}"
end
