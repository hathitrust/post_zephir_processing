require "zlib"
require "date"
require "json"
require "set"

# Consume the latest monthly hathifile

hathifile = "/htapps/archive/hathifiles/hathi_full_20210101.txt.gz"
us_cutoff = Date.today.year.to_i - 95 - 1
non_us_cutoff = Date.today.year.to_i - 140 - 1
can_aus_cutoff = Date.today.year.to_i - 120 - 1
#ntis_cutoff = Date.today.year.to_i - 6 - 1 

# get list of record ids with items that have bib determined rights updates
record_ids = []
Zlib::GzipReader.open(hathifile).each do |line|
  record = line.split("\t")

  bibid = record[3]
  reason_code = record[13]
  rights_date_used = record[16]
  if [us_cutoff, non_us_cutoff, can_aus_cutoff].include? rights_date_used.to_i
    record_ids << bibid    
  end
end

record_id_set = record_ids.uniq.to_set

# get the bib records to give to oai
zeph_recs = "/htapps/archive/catalog/zephir_full_20201231_vufind.json.gz"
found = []
Zlib::GzipReader.open(zeph_recs).each do |line|
  bibid = /"001":"(\d+)"/.match(line)[1]
  if record_id_set.include? bibid
    found << bibid
    puts line
  end
end
