# Compare the existing hathi_upd_YYYYMMDD.txt with what we're generating
# Tally differences
require 'date'
require 'zlib'

yesterday = Date.today.prev_day.strftime("%Y%m%d")
fields = File.open("/l1/govdocs/hathifiles/fields.tsv").read.chomp.split("\t")

newrecs = {} 
newfile = Zlib::GzipReader.open("hathi_upd_#{yesterday}.txt.gz")
newfile.each do |line|
  rec = line.chomp.split("\t")
  newrecs[rec[0]] = rec
end

old = Zlib::GzipReader.open("/htapps/archive/hathifiles/" + 
                             "hathi_upd_#{yesterday}.txt.gz")
field_diff_counts = Hash.new 0
old_ids = []
num_old_missing = 0
old.each do |line|
  old_rec = line.chomp.split("\t")
  old_ids << old_rec[0]
  unless newrecs.key? old_rec[0]
    num_old_missing += 1
    next
  end
  new_rec = newrecs[old_rec[0]]
  fields.each_with_index do |f, index|
    if new_rec[index] != old_rec[index]
      puts [old_rec[0], old_rec[index], new_rec[index]].join("\t")
      field_diff_counts[index] += 1
    end
  end  
end
puts "=================="
puts ""
puts "Date:#{yesterday}"
puts "=================="
puts "Num in OLD:#{old_ids.count}"
puts "Num in New:#{newrecs.keys.count}"
puts "=================="

puts "Field Diff Counts:"
puts "=================="
fields.each_with_index do |f, index|
  puts "#{f}: #{field_diff_counts[index]}"
end

puts "Num old missing from new: #{num_old_missing}"

num_new_missing = 0
newrecs.keys.each do |k|
  num_new_missing += 1 unless old_ids.include? k
  puts newrecs[k].join("\t") unless old_ids.include? k
end
puts "Num new missing from old: #{num_new_missing}"



