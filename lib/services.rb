# frozen_string_literal: true

require "canister"
require "logger"
require "sequel"
require "yaml"

module PostZephirProcessing
  Services = Canister.new

  Services.register(:logger) do
    Logger.new($stdout, level: ENV.fetch("POST_ZEPHIR_PROCESSING_LOGGER_LEVEL", Logger::WARN).to_i)
  end

  # Read-only connection to database for verifying rights DB vs .rights files
  # Would prefer to populate these values from ENV for consistency with other Ruby
  # code running in the workflow but this suffices for now.
  Services.register(:database) do
    database_yaml = File.join(ENV.fetch("ROOTDIR"), "config", "database.yml")
    yaml_data = YAML.load_file(database_yaml)
    Sequel.connect(
      adapter: "mysql2",
      user: yaml_data["user"],
      password: yaml_data["password"],
      host: yaml_data["hostname"],
      database: yaml_data["dbname"],
      encoding: "utf8mb4"
    )
  end
end
