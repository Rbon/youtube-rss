require "open-uri"
require "time"

class Main
  def initialize
    @channel_list_file = "channel_list.txt"
    @time_file = "time.txt"
    @channel_maker = ChannelMaker.new(channel_class: Channel)
    @video_maker = VideoMaker.new(video_class: Video)
  end

  def run
    channel_list = File.readlines(@channel_list_file)
    channel_list.map! { |line| Channel.new(line: line) }
    YoutubeRss.new(
      last_sync_time: Time.parse(File.read(@time_file)),
      channel_list: channel_list,
      video_maker: @video_maker
    ).run
  end
end

class YoutubeRss
  def initialize(opts)
    @video_maker = opts[:video_maker]
    @video_list = []
    @channel_list = opts[:channel_list]
    @entry = false
    @last_sync_time = opts[:last_sync_time]
    puts @last_sync_time.inspect
  end

  def run
    @channel_list.each do |channel|
      # feed = make_feed(channel)
      # puts feed
      # feed = dl_feed(feed)
      feed = File.read("videos.xml")
      @video_list = @video_maker.make_videos(feed)
      dl_videos
    end
    # update_sync_time
  end

  def update_sync_time
    File.open("time.txt", "w") { |file| file.write("#{Time.now.to_s}\n") }
  end


  def dl_feed(feed)
    open(feed)
  end

  def get_videos(feed)
    entry = false
    id = nil
    published = nil
    feed.each_line do |line|
      if entry
        if line.include?("<yt:videoId>")
          id = @id_regex.match(line)[:id]
        end
        if line.include?("<published>")
          published = Time.parse(@time_regex.match(line)[:published])
        end
        if id and published
          @video_list << @video_class.new(id: id, published: published)
          id = nil
          published = nil
        end
      end
      entry = true if line.strip == "<entry>"
    end
  end

  def dl_videos
    @video_list.each do |video|
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

  def make_videos(feed)
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

  def make_channels(file)
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
