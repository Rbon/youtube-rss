require "net/http"
require "time"
require "json"

# Runs the script
class Main
  def initialize(channel_list: ChannelList.new)
    @channel_list = channel_list
  end

  def run
    channel_list.sync
  end

  private

  attr_reader :channel_list
end

# Class to access the user channel list file
class UserChannelList
  def self.path
    File.readlines(File.expand_path("~/.config/youtube-rss/channel_list.txt"))
  end
end

# A list of the channels, as defined by the user's channel list file
class ChannelList
  def initialize(
    channel_list:      UserChannelList.path,
    channel_factory:   ChannelFactory.new)
    @channel_factory = channel_factory
    @channel_list    = channel_list
  end

  def sync
    list.each(&:sync)
  end

  private

  attr_reader :channel_list, :channel_factory

  def list
    channel_list.map { |info| channel_factory.build(info) }
  end
end

# Builds a channel object
class ChannelFactory
  def initialize(
    entry_parser:    EntryParser.new,
    channel_class:   Channel,
    video_factory:   VideoFactory.new)
    @entry_parser  = entry_parser
    @channel_class = channel_class
    @video_factory = video_factory
  end

  def build(info)
    entries = parse_entries(info)
    channel_entry = entries[0]
    video_list = make_video_list(entries.drop(1))
    channel_class.new(
      name: channel_entry[:name],
      video_list: video_list)
  end

  private

  attr_reader :entry_parser, :channel_class, :video_factory

  def parse_entries(info)
    entry_parser.run(info)
  end

  def make_video_list(entries)
    entries.map { |entry| video_factory.build(entry) }
  end
end

# An object which represents the youtube channels.
# Contains a list of its videos, and can sync new videos if they are new
class Channel
  def initialize(name:, video_list:)
    @name       = name
    @video_list = video_list
  end

  def sync
    puts name
    new_videos.each(&:download)
  end

  private

  attr_reader :name, :video_list

  def new_videos
    video_list.select(&:new?)
  end
end

# Creates a valid youtube channel feed URL
class URLMaker
  def run(line)
    line = line.split("#")[0].strip
    type, id = line.split("/")
    URI(feed_types[type.to_sym] % id)
  end

  private

  def feed_types
    {channel: "https://www.youtube.com/feeds/videos.xml?channel_id=%s",
     user:    "https://www.youtube.com/feeds/videos.xml?user=%s"}
  end
end

# Downloads a web page
class PageDownloader
  def initialize(url_maker: URLMaker.new, http: Net::HTTP)
    @url_maker = url_maker
    @http      = http
  end

  def run(url)
    http.get(url)
  end

  private

  attr_reader :url_maker, :http

end

# Takes a youtube channel xml feed and parses it into useful data
class EntryParser
  def initialize(page_downloader: FeedCache.new)
    @tag_regex       = /<(?<tag>.*)>(?<value>.*)<.*>/
    @page_downloader = page_downloader
  end

  def run(info)
    entries(page(info)).map { |entry| parse(entry) }
  end

  private

  attr_reader :tag_regex, :page_downloader

  def page(info)
    page_downloader.run(info)
  end

  def entries(page)
    page.split("<entry>")
  end

  def parse(entry)
    output = {}
    entry.lines.map do |line|
      tag_regex.match(line) do |match|
        tag = match[:tag].tr(":", "_").to_sym
        output[tag] = match[:value]
      end
    end
    output
  end
end

# Builds video objects
class VideoFactory
  def initialize(video_class: Video)
    @video_class = video_class
  end

  def build(entry)
    info = {
      id:           entry[:yt_videoId],
      title:        entry[:title],
      published:    entry[:published],
      channel_name: entry[:name]}
    video_class.new(info: info)
  end

  private

  attr_reader :video_class
end

# An object which contains info about a youtube video
class Video
  def initialize(info:, downloader: VideoDownloader.new, cache: Cache)
    @id           = info[:id]
    @title        = info[:title]
    @published    = Time.parse(info[:published])
    @channel_name = info[:channel_name]
    @downloader   = downloader
    @cache        = cache
  end

  def new?
    published > sync_time(channel_name)
  end

  def download
    downloader.run(id)
    update_cache
  end

  private

  attr_reader :id, :published, :title, :description, :channel_name,
              :cache, :downloader

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
    write(cache)
  end

  def self.sync_time(channel_name:)
    Time.parse(read[channel_name] || "2018-04-18")
  end

  private_class_method

  def self.write(data)
    File.open(CACHE_FILENAME, "w") { |file| JSON.dump(data, file) }
  end

  def self.read
    JSON.parse(File.read(CACHE_FILENAME))
  end
end

# Sends a message to System caller to run youtube-dl
class VideoDownloader
  def run(id)
    SystemCaller.run("youtube-dl \"https://youtu.be/#{id}\"")
  end
end

# Ensures commands are run in the proper directory
class SystemCaller
  def self.run(command)
    dl_path = ARGV[0] || "."
    Dir.chdir(File.expand_path(dl_path)) { system(command) }
  end
end

class FeedCache
  def initialize(
    reader:    FeedCacheReader.new,
    updater:   FeedCacheUpdater.new,
    dir:       "~/.config/youtube-rss/feed-cache")
    @updater = updater
    @reader  = reader
    @dir     = File.expand_path(dir)
  end

  def run(id)
    if !in_cache?(id)
      updater.run(id)
    elsif old?(id)
      updater.run(id)
    elsif empty?(id)
      updater.run(id)
    end
    feed(id)
  end

  private

  attr_reader :updater, :reader, :dir

  def feed(id)
    reader.run(id)
  end

  def in_cache?(id)
    File.file?(path(id))
  end

  def old?(id)
    File.mtime(path(id)) < age_cutoff
  end

  def empty?(id)
    File.zero?(path(id))
  end

  def age_cutoff
    Time.now - 43200
  end

  def path(id)
    "%s/%s" % [dir, strip(id)]
  end

  def strip(id)
    id.split("#")[0].split("/")[1].strip
  end
end

class FeedCacheReader
  def initialize(dir: "~/.config/youtube-rss/feed-cache")
    @dir = File.expand_path(dir)
  end

  def run(id)
    File.read("#{dir}/#{strip(id)}")
  end

  private

  attr_reader :dir

  def strip(id)
    id.split("#")[0].split("/")[1].strip
  end
end

class FeedCacheUpdater
  def initialize(
    dir:          "~/.config/youtube-rss/feed-cache",
    downloader:   FeedDownloader.new)
    @dir        = File.expand_path(dir)
    @downloader = downloader
  end

  def run(id)
    File.open("#{dir}/#{strip(id)}", "w") { |file| file.write(new_feed(id)) }
  end

  private

  attr_reader :dir, :downloader

  def new_feed(id)
    downloader.run(id)
  end

  def strip(id)
    id.split("#")[0].split("/")[1].strip
  end
end

class FeedDownloader
  def initialize(
    page_downloader:   PageDownloader.new,
    url_maker:         URLMaker.new)
    @page_downloader = page_downloader
    @url_maker       = url_maker
  end

  def run(id)
    puts "DOWNLOADING FEED #{id}"
    page(url(id))
  end

  private

  attr_reader :url_maker, :page_downloader

  def page(url)
    page_downloader.run(url)
  end

  def url(id)
    url_maker.run(id)
  end
end
