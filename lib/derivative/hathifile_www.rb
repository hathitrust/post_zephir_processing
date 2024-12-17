require_relative "hathifile"

module PostZephirProcessing
  class Derivative::HathifileWWW < Derivative::Hathifile
    def template
      {
        location: :WWW_DIR,
        name: "hathi_#{fullness}_YYYYMMDD.txt.gz"
      }
    end
  end
end
