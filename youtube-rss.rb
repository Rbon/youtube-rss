require "open-uri"
require "time"

class Main
  def initialize
    @sync_time_file = "time.txt"
    @channel_list_file = File.read("channel_list.txt")
    @video_dlr = VideoDownloader.new(sync_time_file: "time.txt")
    @feed_parser = FeedParser.new(channel_class: Channel, video_class: Video)
  end

  def run
    YoutubeRss.new(
      sync_time_file: @sync_time_file,
      channel_list_file: @channel_list_file,
      video_dlr: @video_dlr,
      feed_parser: @feed_parser
    ).run
  end
end

class YoutubeRss
  def initialize(opts)
    @sync_time_file = opts[:sync_time_file]
    @channel_list_file = opts[:channel_list_file]
    @feed_parser = opts[:feed_parser]
    @video_dlr = opts[:video_dlr]
  end

  def run
    @channel_list_file.each_line do |line|
      # feed = open(make_feed(channel))
      # feed = File.read("videos.xml")
      channel = @channel_class.new(line: line, video_class: @video_class)
      puts channel.video_list[0].published
      @video_dlr.dl(channel.video_list)
    end
    File.write(@sync_time_file, Time.now)
  end

  def run
    feed = File.read("videos.xml")
    channel = @feed_parser.channel(feed)
    puts channel.video_list[0].title
  end
end

class FeedParser
  def initialize(opts)
    @channel_class = opts[:channel_class]
    @video_class = opts[:video_class]
    @tag_regex = /<(?<tag>.*)>(?<value>.*)<.*>/
  end

  def channel(feed)
    feed = feed.split("<entry>")
    data = {}
    feed[0].lines do |line|
      @tag_regex.match(line) { |match| data[match[:tag]] = match[:value] }
    end
    video_list = feed.drop(1).map { |entry| video(entry) }
    @channel_class.new(
      id: data["yt:channelId"],
      name: data["name"],
      video_list: video_list
    )
  end

  def video(info)
    data = {}
    info.lines do |line|
      @tag_regex.match(line) { |match| data[match[:tag]] = match[:value] }
    end
    @video_class.new(
      id: data["yt:videoId"],
      title: data["title"],
      published: data["published"]
    )
  end
end

class Channel
  attr_reader :video_list, :name, :id

  def initialize(opts)
    @id = opts[:id]
    @name = opts[:name]
    @video_list = opts[:video_list]
  end
end

class Video
  attr_reader :id, :published, :title, :description

  def initialize(opts)
    @id = opts[:id]
    @title = opts[:title]
    @description = opts[:description]
    @published = opts[:published]
  end
end

class XMLGetter
  def initialize
    # @feed = open({
      # channel: "https://www.youtube.com/feeds/videos.xml?channel_id=#{id}",
      # user: "https://www.youtube.com/feeds/videos.xml?user=#{id}"
    # }[type])
  end
end

class VideoDownloader
  def initialize(opts)
    @last_sync_time = Time.parse(File.read(opts[:sync_time_file]))
    puts "Last sync time: #{@last_sync_time}"
  end

  def dl(video_list)
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

Main.new.run
