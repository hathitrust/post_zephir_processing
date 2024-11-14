# frozen_string_literal: true

require "canister"
require "logger"

module PostZephirProcessing
  Services = Canister.new

  Services.register(:logger) do
    Logger.new($stdout, level: ENV.fetch("POST_ZEPHIR_PROCESSING_LOGGER_LEVEL", Logger::WARN).to_i)
  end
end
