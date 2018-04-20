### BUGS: If youtube-dl isn't present, the script thinks everything is fine, and
###       updates the sync dates.

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

class ChannelList
  def initialize(channel_list: File.readlines(File.expand_path(
                   "~/.config/youtube-rss/channel_list.txt")),
                 channel_factory: ChannelFactory.new)

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

class ChannelFactory
  def initialize(entry_parser: EntryParser.new,
                 channel_class: Channel,
                 video_factory: VideoFactory.new)

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

  def run(info)
    http.get(url(info))
  end

  private

  attr_reader :url_maker, :http

  def url(info)
    url_maker.run(info)
  end
end



class EntryParser
  def initialize(page_downloader: PageDownloader.new)
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
        tag = match[:tag].gsub(":", "_").to_sym
        output[tag] = match[:value]
      end
    end
    output
  end
end

class VideoFactory
  def initialize(video_class: Video)
    @video_class = video_class
  end

  def build(entry)
    video_class.new(
      id:           entry[:yt_videoId],
      title:        entry[:title],
      published:    entry[:published],
      channel_name: entry[:name])
  end

  private

  attr_reader :video_class
end

class Video
  def initialize(id:, title:, published:, channel_name:,
                 downloader: VideoDownloader.new, cache: Cache)

    @id           = id
    @title        = title
    @published    = Time.parse(published)
    @channel_name = channel_name
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
