### https://www.youtube.com/feeds/videos.xml?channel_id=UCTjqo_3046IXFFGZ_M5jedA

require "date"
class Main
  def initialize
    @file = File.read(ARGV[0])
    @id_regex = Regexp.new("<yt:videoId>(?<id>.*)<\/yt:videoId>")
    @videos = nil
  end

  def run
    get_list
    dl_video
  end

  def get_list
    @file.each_line do |line|
      if line.include?("<yt:videoId>")
        @video = @id_regex.match(line)[:id]
        return
      end
    end
  end

  def dl_video
    if check_video(@video) == false
      system("youtube-dl #{@video}")
      add_to_db(@video)
      puts "ADDED TO DB"
    end
  end

  def check_video(id)
    dldb = File.readlines("dldb.txt").reverse
    return dldb.include?("#{id}\n")
  end

  def add_to_db(id)
    File.open("dldb.txt", "a") { |file| file.write("#{id}\n") }
  end
end

Main.new.run
