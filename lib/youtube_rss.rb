### BUGS: If youtube-dl isn't present, the script thinks everything is fine, and
###       updates the sync dates.

require "net/http"
require "time"
require "json"

# Runs the script
class Main
  attr_reader :channel_list, :channel_factory

  def initialize(channel_factory: ChannelFactory.new, channel_list: nil)
    @dl_path = ARGV[0] || "."
    @channel_list = channel_list || File.readlines(
      File.expand_path("~/.config/youtube-rss/channel_list.txt"))
    @channel_factory = channel_factory
  end

  def run
    channel_list.each { |line| tick(line) }
  end

  private

  def tick(line)
    channel = make_channel(line)
    puts channel.name
    channel.new_videos.each(&:download)
  end

  def make_channel(line)
    channel_factory.for(line)
  end
end

# Creates a valid youtube channel feed URL
class URLMaker
  def run(line)
    line = line.split("#")[0].strip
    type, id = line.split("/")
    feed_types[type.to_sym] % id
  end

  private

  def feed_types
    {channel: "https://www.youtube.com/feeds/videos.xml?channel_id=%s",
     user: "https://www.youtube.com/feeds/videos.xml?user=%s"}
  end
end

# Downloads a web page
class HTTPDownloader
  def initialize(url_maker: URLMaker.new)
    @url_maker = url_maker
  end

  def run(line)
    Net::HTTP.get(URI(url(line)))
  end

  private

  def url(line)
    @url_maker.run(line)
  end
end

# Makes a Channel class
class ChannelFactory
  def initialize(feed_parser: FeedParser.new)
    @feed_parser = feed_parser
  end

  def for(line)
    channel_info, video_info_list = feed(line)
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

  private

  def feed(line)
    @feed_parser.run(line)
  end
end

# Lazily parses xml files into the relevant info
class FeedParser
  def initialize(http_downloader: HTTPDownloader.new)
    @tag_regex = /<(?<tag>.*)>(?<value>.*)<.*>/
    @http_downloader = http_downloader
  end

  def run(line)
    info_list(entries(page(line)))
  end

  private

  def page(line)
    @http_downloader.run(line)
  end

  def info_list(entries)
    {channel_info: channel_info(entries),
     video_info_list: video_info_list(entries)}
  end

  def channel_info(entries)
    info(entries[0])
  end

  def video_info_list(entries)
    entries.drop(1).map { |entry| info(entry) }
  end

  def entries(feed)
    feed.split("<entry>")
  end

  def info(entry)
    output = {}
    entry.lines do |line|
      @tag_regex.match(line) { |match| output[match[:tag]] = match[:value] }
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

  def download
    downloader.run(id)
    update_cache
  end

  private

  def sync_time(channel_name)
    cache.sync_time(channel_name: channel_name)
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

  def self.sync_time(channel_name:)
    Time.parse(read[channel_name] || "2018-03-01")
  end

  private_class_method

  def self.write(data)
    File.open(CACHE_FILENAME, "w") { |file| JSON.dump(data, file) }
  end

  def self.read
    JSON.parse(File.read(CACHE_FILENAME))
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
