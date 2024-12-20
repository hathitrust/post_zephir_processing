#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs run_zephir_full_monthly.sh and/or run_process_zephir_incremental.sh
# for any dates that are missing from the current inventory of derivative files.

require "date"
require "logger"

require_relative "../lib/dates"
require_relative "../lib/post_zephir_derivatives"
require_relative "../lib/journal"

def run_system_command(command)
  LOGGER.info command
  system(command, exception: true)
end

LOGGER = Logger.new($stdout, level: ENV.fetch("POST_ZEPHIR_LOGGER_LEVEL", Logger::INFO).to_i)
HOME = File.expand_path(File.join(__dir__, "..")).freeze
FULL_SCRIPT = File.join(HOME, "run_zephir_full_monthly.sh")
INCREMENTAL_SCRIPT = File.join(HOME, "run_process_zephir_incremental.sh")
YESTERDAY = Date.today - 1

derivatives = PostZephirProcessing::PostZephirDerivatives.new
dates = []
# Is there a missing date? Plug them into an array to process.
if !derivatives.earliest_missing_date.nil?
  dates = ((derivatives.earliest_missing_date - 1)..YESTERDAY)
end

LOGGER.info "Processing Zephir files from #{dates}"
dates.each do |date|
  date_str = date.strftime("%Y%m%d")
  LOGGER.info "Processing Zephir file for #{date_str}"
  if date.last_of_month?
    run_system_command "#{FULL_SCRIPT} #{date_str}"
  end
  run_system_command "#{INCREMENTAL_SCRIPT} #{date_str}"
end

# Record our work for the verifier
LOGGER.info "Writing journal for #{dates}"
# TODO: consider moving the `to_a` to the Journal initializer so it can take
# Ranges as well as Arrays
PostZephirProcessing::Journal.new(dates: dates.to_a).write!
