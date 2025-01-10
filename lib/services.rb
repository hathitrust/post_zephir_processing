# frozen_string_literal: true

require "canister"
require "logger"
require "sequel"

module PostZephirProcessing
  Services = Canister.new

  Services.register(:logger) do
    Logger.new($stdout, level: ENV.fetch("POST_ZEPHIR_PROCESSING_LOGGER_LEVEL", Logger::WARN).to_i)
  end

  # Read-only connection to database for verifying rights DB vs .rights files
  # as well as hathifiles tables.
  Services.register(:database) do
    Sequel.connect(
      adapter: "mysql2",
      user: ENV["DB_HT_RO_USER"],
      password: ENV["DB_HT_RO_PASSWORD"],
      host: ENV["DB_HT_RO_HOST"],
      port: ENV["DB_HT_RO_PORT"],
      database: ENV["DB_HT_RO_DATABASE"],
      encoding: "utf8mb4"
    )
  end
end
