require "open-uri"
require "time"

class Main
  def initialize
    @sync_time_file = "time.txt"
    @channel_list_file = "channel_list.txt"
    @channel_maker = ChannelMaker.new(channel_class: Channel)
    @video_maker = VideoMaker.new(video_class: Video)
    @video_dlr = VideoDownloader.new(sync_time_file: "time.txt")
  end

  def run
    YoutubeRss.new(
      sync_time_file: @sync_time_file,
      channel_list_file: @channel_list_file,
      channel_maker: @channel_maker,
      video_maker: @video_maker,
      video_dlr: @video_dlr
    ).run
  end
end

class YoutubeRss
  def initialize(opts)
    @sync_time_file = opts[:sync_time_file]
    @channel_list_file = opts[:channel_list_file]
    @channel_maker = opts[:channel_maker]
    @video_maker = opts[:video_maker]
    @video_dlr = opts[:video_dlr]
  end

  def run
    @channel_maker.list(@channel_list_file).each do |channel|
      # feed = open(make_feed(channel))
      feed = File.read("videos.xml")
      @video_dlr.dl_videos(@video_maker.list(feed))
    end
    File.write(@sync_time_file, Time.now)
  end
end

class VideoDownloader
  def initialize(opts)
    @last_sync_time = Time.parse(File.read(opts[:sync_time_file]))
    puts "Last sync time: #{@last_sync_time}"
  end

  def dl_videos(video_list)
    video_list.each do |video|
      if video.published > @last_sync_time
        if check_video(video.id) == false
          system("youtube-dl #{video.id}")
          add_to_db(video.id)
          puts "ADDED TO DB"
        end
      end
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

class VideoMaker
  def initialize(opts)
    @video_class = opts[:video_class]
    @id_regex = Regexp.new("<yt:videoId>(?<id>.*)<\/yt:videoId>")
    @time_regex = Regexp.new("<published>(?<published>.*)<\/published>")
  end

  def list(feed)
    entry = false
    id = nil
    published = nil
    video_list = []
    feed.each_line do |line|
      if entry
        if line.include?("<yt:videoId>")
          id = @id_regex.match(line)[:id]
        end
        if line.include?("<published>")
          published = Time.parse(@time_regex.match(line)[:published])
        end
        if id and published
          video_list << @video_class.new(id: id, published: published)
          id = nil
          published = nil
        end
      end
      entry = true if line.strip == "<entry>"
    end
    video_list
  end
end

class ChannelMaker
  def initialize(opts)
    @channel_class = opts[:channel_class]
  end

  def list(file)
    File.readlines(file).map { |line| @channel_class.new(line: line) }
  end
end

class Channel
  def initialize(opts)
    type, id = opts[:line].split("#")[0].split("/")
    @feed = {
      channel: "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}",
      user: "https://www.youtube.com/feeds/videos.xml?user=#{id}"
    }[type]
  end
end

class Video
  attr_reader :id, :published

  def initialize(opts)
    @id = opts[:id]
    @published = opts[:published]
  end
end

Main.new.run
