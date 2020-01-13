# Compare the existing zephir_upd_YYYYMMDD.txt with what we're generating
# Tally differences
require 'date'
require 'zlib'
require 'json'
require 'marc'

yesterday = Date.today.prev_day.strftime("%Y%m%d")

old = Zlib::GzipReader.open("/htapps/archive/catalog/" +
                            "zephir_upd_#{yesterday}.json.gz")
new = Zlib::GzipReader.open("zephir_upd_#{yesterday}.json.gz")

old_count = 0
same_count = 0
diff_count = 0
old.each do |line|
  old_rec = MARC::Record.new_from_hash(JSON.parse(line))
  new_rec = MARC::Record.new_from_hash(JSON.parse(new.readline))
  if old_rec == new_rec
    same_count += 1 
  else
    diff_count += 1 
  end
end

unless new.eof?
  puts "New file has more records than the old one!"
end

puts "Num Same:#{same_count}"
puts "Num Diff:#{diff_count}"
