# frozen_string_literal: true

require "fileutils"
require_relative "services"

class PostZephirProcessing
  ZEPHIR_DATE_RE = /YYYY-MM-DD/
  DOWNLOADS = {
    export: {
      template: "ht_bib_export_incr_YYYY-MM-DD.json.gz",
      die_on_error: true,
      destination: nil
    },
    deletes: {
      template: "vufind_removed_cids_YYYY-MM-DD.txt.gz",
      die_on_error: true,
      destination: nil
    },
    groove: {
      template: "groove_incremental_YYYY-MM-DD.tsv.gz",
      die_on_error: false,
      destination: Services[:ingest_bibrecords]
    },
    touched: {
      template: "daily_touched_YYYY-MM-DD.tsv.gz",
      die_on_error: false,
      destination: Services[:ingest_bibrecords]
    }
  }
  attr_reader :date, :logger

  def initialize(date:, logger:)
    @date = date
    @logger = logger.nil? ? Logger.new : logger
  end

  def zephir_date
    @zephir_date ||= date.strftime("%Y-%m-%d")
  end

  def ht_date
    @ht_date ||= date.strftime("%Y%m%d")
  end

  def zephir_export_file
    @zephir_export_file ||= tempdir_path(DOWNLOADS[:export][:template].sub(ZEPHIR_DATE_RE, zephir_date))
  end

  def zephir_deletes_file
    @zephir_deletes_file ||= tempdir_path(DOWNLOADS[:deletes][:template].sub(ZEPHIR_DATE_RE, zephir_date))
  end

  # zephir_upd_YYYYMMDD
  def basename
    @basename ||= "zephir_upd_#{ht_date}"
  end

  # zephir_upd_YYYYMMDD.json
  def json_file
    @json_file ||= tempdir_path("#{basename}.json")
  end

  # zephir_upd_YYYYMMDD.json.gz
  def json_gz_file
    @json_gz_file ||= tempdir_path("#{basename}.json.gz")
  end

  # Decompressed zephir_deletes_file prior to sort/unique.
  def delete_file
    @delete_file ||= tempdir_path("#{basename}_zephir_delete.txt")
  end

  # Sorted/unique text file before compression and move to catalog prep.
  def all_delete_file
    @all_delete_file ||= tempdir_path("#{basename}_all_delete.txt")
  end

  # Locate a file in the work/tmp directory
  def tempdir_path(file)
    File.join(Services[:tmpdir], file)
  end

  # This should be independent of any particular date.
  def dump_rights
    logger.info "dump rights db to dbm file"
    cmd = [
      File.join(Services[:home], "bld_rights_db.pl"),
      "-x",
      Services[:rights_dbm],
      "2>&1"
    ].join(" ")
    run_command(cmd)
  end

  def run
    process_zephir_export_file
    process_zephir_deletes

    logger.info "move rights file #{basename}.rights to rights_dir #{Services[:rights_dir]}"
    FileUtils.mv(tempdir_path("#{basename}.rights"), Services[:rights_dir])

    logger.info "compress JSON file"
    run_command("gzip -n -f #{json_file}")

    logger.info "copy JSON file to catalog prep"
    FileUtils.cp(json_gz_file, Services[:catalog_prep])

    logger.info "copy JSON file to catalog archive"
    FileUtils.cp(json_gz_file, Services[:catalog_archive])

    logger.info "send combined delete file to catalog prep as #{basename}_delete.txt.gz"
    FileUtils.mv(all_delete_file, File.join(Services[:catalog_prep], "#{basename}_delete.txt.gz"))

    logger.info "compress dollar dup files and send to zephir"
    dollar_dupe_out = "vufind_incremental_YYYY-MM-DD_dollar_dup.txt".sub(ZEPHIR_DATE_RE, zephir_date)
    FileUtils.mv(tempdir_path("#{basename}_dollar_dup.txt"), tempdir_path(dollar_dupe_out))
    cmd = "gzip -f -n #{tempdir_path(dollar_dupe_out)}"
    run_command(cmd)
    cmd = [
      Services[:ftps_zephir_send],
      tempdir_path(dollar_dupe_out + ".gz")
    ].join(" ")
    run_command(cmd, noop: true)

    logger.info "Remove #{json_gz_file}"
    FileUtils.rm json_gz_file
  end

  def download_zephir_files
    DOWNLOADS.each do |key, download|
      file = download[:template].sub(ZEPHIR_DATE_RE, zephir_date)
      local_file = tempdir_path(file)
      logger.debug("Checking for existence of #{key} => #{local_file}")
      if File.exist? local_file
        logger.info "Zephir file #{local_file} already exists, skipping"
        next
      end

      cmd = Services[:ftps_zephir_get] + " exports/#{file} #{local_file}"
      run_command(cmd, die_on_error: download[:die_on_error])
      FileUtils.mv(file, download[:destination]) unless download[:destination].nil?
    end
  end

  private

  # Run postZephir.pm on the main export file
  def process_zephir_export_file
    logger.info "processing file #{zephir_export_file}"
    cmd = [
      File.join(Services[:home], "postZephir.pm"),
      "-i",
      zephir_export_file,
      "-o",
      tempdir_path(basename),
      "-r",
      tempdir_path("#{basename}.rights"),
      "-d",
      "-f",
      Services[:rights_dbm],
      "2>&1"
    ].join(" ")
    run_command(cmd)
  end

  # Decompress vufind_removed_cids_YYYY-MM-DD.txt.gz to zephir_upd_YYYYMMDD_zephir_delete.txt
  # Sort/unique zephir_upd_YYYYMMDD_zephir_delete.txt to zephir_upd_YYYYMMDD_all_delete.txt
  # Compress zephir_upd_YYYYMMDD_all_delete.txt to zephir_upd_YYYYMMDD_all_delete.txt.gz
  # (Will be renamed to zephir_upd_YYYYMMDD_delete.txt.gz later when moved to catalog prep.)
  def process_zephir_deletes
    cmd = "zcat #{zephir_deletes_file} > #{delete_file}"
    run_command(cmd)
    cmd = "sort -u #{delete_file} -o #{all_delete_file}"
    run_command(cmd)
    cmd = "gzip -f #{all_delete_file}"
    run_command(cmd)
  end

  def run_command(cmd, die_on_error: true, noop: false)
    logger.debug "calling #{cmd}"
    cmd = noop ? ":" : cmd
    output = `#{cmd}`
    if $? != 0
      logger.error "exitstatus #{$?.exitstatus} from #{cmd}"
      exit(1) if die_on_error
    end
    if output.length.positive?
      logger.info("#{cmd} output: \n#{output}")
    end
  end
end
