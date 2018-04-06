require "net/http"
require "time"
require "json"

# Runs the script
class Main
  def initialize
    @dl_path = ARGV[0] || "."
    @channel_list = File.readlines(
      File.expand_path("~/.config/youtube-rss/channel_list.txt"))
  end

  def run
    @channel_list.each do |line|
      url = FeedGenerator.run(line)
      feed = HTTPDownloader.run(url)
      parsed_feed = FeedParser.parse(feed)
      channel = ChannelFactory.for(parsed_feed)
      puts channel.name
      channel.new_videos.each(&:download)
    end
  end
end

# Creates a valid youtube channel feed URL
class FeedGenerator
  FEED_TYPES = {
    channel: "https://www.youtube.com/feeds/videos.xml?channel_id=%s",
    user: "https://www.youtube.com/feeds/videos.xml?user=%s"}.freeze

  def self.run(url)
    url = url.split("#")[0].strip
    type, id = url.split("/")
    FEED_TYPES[type.to_sym] % id
  end
end

# Downloads a web page
class HTTPDownloader
  def self.run(url)
    Net::HTTP.get(URI(url))
  end
end

# Makes a Channel class
class ChannelFactory
  def self.for(channel_info:, video_info_list:)
    video_list = video_info_list.reverse.map do |video_info|
      Video.new(
        info: video_info,
        channel_name: channel_info["name"])
    end
    Channel.new(
      id: channel_info["yt:channelId"],
      name: channel_info["name"],
      video_list: video_list)
  end
end

# Lazily parses xml files into the relevant info
class FeedParser
  TAG_REGEX = /<(?<tag>.*)>(?<value>.*)<.*>/

  def self.parse(feed)
    feed = feed.split("<entry>")
    channel_info = make_info(feed[0])
    video_info_list = feed.drop(1).map { |entry| make_info(entry) }
    {channel_info: channel_info, video_info_list: video_info_list}
  end

  private_class_method

  def self.make_info(entry)
    info = {}
    entry.lines do |line|
      TAG_REGEX.match(line) { |match| info[match[:tag]] = match[:value] }
    end
    info
  end
end

# An object which contains channel info, and a list of video objects
class Channel
  attr_reader :name, :id, :video_list

  def initialize(id:, name:, video_list:)
    @id = id
    @name = name
    @video_list = video_list
  end

  def new_videos
    @video_list.select(&:new?)
  end
end

# An object which contains video info, and some methods related to downloading
class Video
  attr_reader :id, :published, :title, :description

  def initialize(info:, channel_name:, downloader: VideoDownloader.new)
    @id = info["yt:videoId"]
    @title = info["title"]
    @description = info["description"]
    @published = Time.parse(info["published"])
    @channel_name = channel_name
    @downloader = downloader
  end

  def new?
    @published > Cache.sync_time(channel_name: @channel_name)
  end

  def download
    @downloader.run(id: @id)
    Cache.update(time: @published, channel_name: @channel_name)
  end
end

# A class which represents the cache file used for this script.
# Contains methods for reading and writing to the cache file.
class Cache
  CACHE_FILENAME = File.expand_path("~/.config/youtube-rss/cache.json")

  def self.update(time:, channel_name:)
    cache = File.read(CACHE_FILENAME)
    cache = JSON.parse(cache)
    cache[channel_name] = time
    file = File.open(CACHE_FILENAME, "w")
    JSON.dump(cache, file)
    file.close
  end

  def self.sync_time(channel_name:)
    time = File.read(CACHE_FILENAME)
    time = JSON.parse(time)[channel_name]
    Time.parse(time || "2018-04-05")
  end
end

# Calls SystemCaller with a youtube-dl command
class VideoDownloader
  def run(id:)
    SystemCaller.run("youtube-dl #{id}")
  end
end

# Runs a command with system, and stops the program if something goes wrong
class SystemCaller
  DL_PATH = (ARGV[0] || ".").freeze

  def self.run(command)
    Dir.chdir(File.expand_path(DL_PATH)) do
      status = system(command)
      unless status
        puts "ERROR"
        exit
      end
    end
  end
end
