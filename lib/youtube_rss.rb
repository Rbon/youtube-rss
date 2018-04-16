### BUGS: If youtube-dl isn't present, the script thinks everything is fine, and
###       updates the sync dates.

require "net/http"
require "time"
require "json"

# Runs the script
class Main
  attr_reader :channel_list, :url_maker, :http_downloader, :feed_parser,
              :channel_factory

  def initialize
    @dl_path = ARGV[0] || "."
    @channel_list = File.readlines(
      File.expand_path("~/.config/youtube-rss/channel_list.txt"))
    @url_maker = URLMaker
    @http_downloader = HTTPDownloader
    @feed_parser = FeedParser
    @channel_factory = ChannelFactory
  end

  def run
    channel_list.each { |line| tick(line) }
  end

  def tick(line)
    channel = make_channel(line)
    puts channel.name
    channel.new_videos.each(&:download)
  end

  def url(line)
    url_maker.run(line)
  end

  def page(line)
    http_downloader.run(url(line))
  end

  def feed(line)
    feed_parser.parse(page(line))
  end

  def make_channel(line)
    channel_factory.for(feed(line))
  end
end

# Creates a valid youtube channel feed URL
class URLMaker
  FEED_TYPES = {
    channel: "https://www.youtube.com/feeds/videos.xml?channel_id=%s",
    user: "https://www.youtube.com/feeds/videos.xml?user=%s"}.freeze

  def self.run(line)
    line = line.split("#")[0].strip
    type, id = line.split("/")
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
    info_list(entries(feed))
  end

  private_class_method

  def self.info_list(entries)
    {channel_info: channel_info(entries),
     video_info_list: video_info_list(entries)}
  end

  def self.channel_info(entries)
    info(entries[0])
  end

  def self.video_info_list(entries)
    entries.drop(1).map { |entry| info(entry) }
  end

  def self.entries(feed)
    feed.split("<entry>")
  end

  def self.info(entry)
    output = {}
    entry.lines do |line|
      TAG_REGEX.match(line) { |match| output[match[:tag]] = match[:value] }
    end
    output
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
    video_list.select(&:new?)
  end
end

# An object which contains video info, and some methods related to downloading
class Video
  attr_reader :id, :published, :title, :description, :channel_name,
    :downloader, :cache

  def initialize(info:, channel_name:, downloader: VideoDownloader.new)
    @id = info["yt:videoId"]
    @title = info["title"]
    @description = info["description"]
    @published = Time.parse(info["published"])
    @channel_name = channel_name
    @downloader = downloader
    @cache = Cache
  end

  def new?
    published > sync_time(channel_name)
  end

  def sync_time(channel_name)
    cache.sync_time(channel_name: channel_name)
  end

  def download
    downloader.run(id)
    update_cache
  end

  def update_cache
    cache.update(time: published, channel_name: channel_name)
  end
end

# A class which represents the cache file used for this script.
# Contains methods for reading and writing to the cache file.
class Cache
  CACHE_FILENAME = File.expand_path("~/.config/youtube-rss/cache.json")

  def self.update(time:, channel_name:)
    cache = read
    cache[channel_name] = time
    self.write(cache)
  end

  def self.write(data)
    File.open(CACHE_FILENAME, "w") { |file| JSON.dump(data, file) }
  end

  def self.read
    JSON.parse(File.read(CACHE_FILENAME))
  end

  def self.sync_time(channel_name:)
    Time.parse(read[channel_name] || "2018-03-01")
  end
end

# An object which runs youtube-dl
class VideoDownloader
  attr_reader :dl_path

  def initialize
    @dl_path = ARGV[0] || "."
  end

  def run(id)
    Dir.chdir(File.expand_path(dl_path)) { system("youtube-dl #{id}") }
  end
end
