# frozen_string_literal: true

require "canister"
require "dotenv"

# Load order to honor dependencies:
#  Home so we know where to look for everything else.
#  Env so we can set up DB and Solr config
HOME = File.expand_path(File.join(__dir__, "..")).freeze

# Note: this is cribbed from hathitrust_catalog_indexer and is unused here,
# since the existing system has its own way of doing config.
# I'm leaving it here in the hope that it may be useful.
module Env
  # Load env file and env.local if it exists.
  # Precedence from high to low:
  #  ENV set by Docker, docker-compose, kubectl, etc.
  #  config/env.local for non-k8s production use
  #  config/env which has defaults for development and testing
  def env_file
    @env_file ||= File.join(HOME, "config", "env")
  end

  def env_local_file
    @env_local_file ||= File.join(HOME, "config", "env.local")
  end

  module_function :env_file, :env_local_file
  # From the Dotenv README: "The first value set for a variable will win."
  Dotenv.load env_local_file, env_file
end

Services = Canister.new

# The top-level repo path.
# In Docker likely to be "/usr/src/app/"
Services.register(:home) do
  HOME
end

Services.register(:catalog_archive) do
  ENV["CATALOG_ARCHIVE"] || File.join(Services[:data_root], "catalog_archive")
end

Services.register(:catalog_prep) do
  ENV["CATALOG_PREP"] || File.join(Services[:data_root], "catalog_prep")
end

Services.register(:data_root) do
  ENV["DATA_ROOT"] || File.join(HOME, "data")
end

Services.register(:ftps_zephir_get) do
  File.join(HOME, "ftpslib", "ftps_zephir_get")
end

Services.register(:ftps_zephir_send) do
  File.join(HOME, "ftpslib", "ftps_zephir_send")
end

Services.register(:ingest_bibrecords) do
  ENV["INGEST_BIBRECORDS"] || File.join(Services[:data_root], "ingest_bibrecords")
end

Services.register(:rights_dbm) do
  ENV["RIGHTS_DBM"] || File.join(Services[:data_root], "rights_dbm")
end

Services.register(:rights_dir) do
  ENV["RIGHTS_DIR"] || File.join(Services[:data_root], "rights")
end

Services.register(:tmpdir) do
  ENV["TMPDIR"] || File.join(Services[:data_root], "work")
end
