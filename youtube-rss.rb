require "date"
require "open-uri"

class Main
  def initialize
    @file = File.read(ARGV[0])
    @id_regex = Regexp.new("<yt:videoId>(?<id>.*)<\/yt:videoId>")
    @videos = nil
    @channel_list = File.readlines("channel_list.txt")
  end

  def run
    @channel_list.each do |channel|
      feed = make_feed(channel)
      feed = dl_feed(feed)
      get_video(feed)
      dl_video
    end
  end

  def make_feed(channel)
    type, id = channel.split("/")
    case type
    when "channel"
      return "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}"
    when "user"
      return "https://www.youtube.com/feeds/videos.xml?user=#{id}"
    end
  end

  def dl_feed(feed)
    open(feed)
  end

  def get_video(feed)
    feed.each_line do |line|
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
