require "open-uri"
require "time"

class Main
  def initialize
    @sync_time_file = "time.txt"
    @dldb_file = "dldb.txt"
    @channel_list_file = File.read("channel_list.txt")
    @feed_parser = FeedParser.new(
      channel_class: Channel,
      video_class: Video,
      last_sync_time: Time.parse(File.read(@sync_time_file)),
      dldb_file: @dldb_file
    )
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
    @channel_list = ["test"]
    @feed_parser = opts[:feed_parser]
    @video_dlr = opts[:video_dlr]
  end

  def run
    puts File.read(@sync_time_file)
    @channel_list.each do |line|
      feed = File.read("videos.xml")
      channel = @feed_parser.channel(feed)
      puts channel.name
      channel.video_list.each(&:download)
    end
    File.write(@sync_time_file, Time.now)
  end
end

class FeedParser
  def initialize(opts)
    @channel_class = opts[:channel_class]
    @video_class = opts[:video_class]
    @tag_regex = /<(?<tag>.*)>(?<value>.*)<.*>/
    @last_sync_time = opts[:last_sync_time]
    @dldb_file = opts[:dldb_file]
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

  private

  def video(info)
    data = {}
    info.lines do |line|
      @tag_regex.match(line) { |match| data[match[:tag]] = match[:value] }
    end
    id = data["yt:videoId"]
    published = Time.parse(data["published"])
    @video_class.new(
      id: id,
      title: data["title"],
      published: published,
      dldb_file: @dldb_file,
      last_sync_time: @last_sync_time
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
    @last_sync_time = opts[:last_sync_time]
    @dldb_file = opts[:dldb_file]
  end

  def download
    puts "Checking video: #{@title}"
    send("download_when_#{not (old? or in_cache?)}")
  end

  private

  def download_when_true
    puts "Downloading: #{@title}"
    system("youtube-dl #{@id}")
    File.open(@dldb_file, "a") { |file| file.write("#{@id}\n") }
  end

  def download_when_false
    puts "Not downloading: #{@title}"
  end

  def old?
    @last_sync_time > @published
  end

  def in_cache?
    @dldb_file.readlines.include?("#{@id}\n")
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

Main.new.run
