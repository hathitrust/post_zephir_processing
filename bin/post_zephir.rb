#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs run_zephir_full_monthly.sh and/or run_process_zephir_incremental.sh
# for any dates that are missing from the current inventory of derivative files.

require "date"
require "logger"

require_relative "../lib/dates"
require_relative "../lib/derivatives"

def run_system_command(command)
  LOGGER.info command
  system(command, exception: true)
end

LOGGER = Logger.new($stdout, level: ENV.fetch("POST_ZEPHIR_LOGGER_LEVEL", Logger::INFO).to_i)
HOME = File.expand_path(File.join(__dir__, "..")).freeze
FULL_SCRIPT = File.join(HOME, "run_zephir_full_monthly.sh")
INCREMENTAL_SCRIPT = File.join(HOME, "run_process_zephir_incremental.sh")
YESTERDAY = Date.today - 1

inventory = PostZephirProcessing::Derivatives.new(date: YESTERDAY)
LOGGER.info "all existing Zephir full files: #{inventory.full_derivatives}"
LOGGER.info "all existing Zephir updates: #{inventory.update_derivatives}"

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
