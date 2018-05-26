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
class FeedList
  def initialize(
    feed_class:   Feed,
    list_file:    "~/.config/youtube-rss/channel_list.txt")
    @feed_class = feed_class
    @list_file  = list_file
  end

  def list
    file_lines.map { |line| feed_class.new(info: line) }
  end

  private

  attr_reader :list_file, :feed_class

  def file_lines
    File.readlines(File.expand_path(list_file))
  end
end

class Feed
  attr_reader :id, :type, :comment

  def initialize(
    info:,
    dir:       "~/.config/youtube-rss/feed-cache")
    @info    = info
    @dir     = File.expand_path(dir)
    @id      = info.split("#")[0].split("/")[1].strip
    @type    = info.split("#")[0].split("/")[0].strip
    @comment = info.split("#")[1].strip
  end

  def in_cache?
    File.file?(path)
  end

  def old?
    File.mtime(path) < age_cutoff
  end

  def empty?
    File.zero?(path)
  end

  private

  attr_reader :info, :dir

  def age_cutoff
    Time.now - 43200
  end

  def path
    "%s/%s" % [dir, id]
  end
end

# A list of the channels, as defined by the user's channel list file
class ChannelList
  def initialize(
    feed_list:       FeedList.new.list,
    channel_class:   Channel)
    @channel_class = channel_class
    @feed_list     = feed_list
  end

  def sync
    list.each(&:sync)
  end

  private

  attr_reader :feed_list, :channel_class

  def list
    feed_list.map { |feed| channel_class.new(feed: feed) }
  end
end

# An object which represents the youtube channels.
# Contains a list of its videos, and can sync new videos if they are new
class Channel
  def initialize(
    feed:,
    entry_parser:    EntryParser.new,
    video_factory:   VideoFactory.new)
    @feed          = feed
    @entry_parser  = entry_parser
    @video_factory = video_factory
  end

  def sync
    puts name
    new_videos.each(&:download)
  end

  private

  attr_reader :feed, :entry_parser, :video_factory

  def name
    info[:name]
  end

  def info
    @info ||= entries[0]
  end

  def new_videos
    video_list.select(&:new?)
  end

  def video_list
    entries.drop(1).map { |entry| video_factory.build(entry) }.reverse
  end

  def entries
    @entries ||= entry_parser.run(feed)
  end
end

# Creates a valid youtube channel feed URL
class URLMaker
  def run(id:, type:)
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

  def run(feed)
    entries(page(feed)).map { |entry| parse(entry) }
  end

  private

  attr_reader :tag_regex, :page_downloader

  def page(feed)
    page_downloader.run(feed)
  end

  def entries(page)
    page.split("<entry>")
  end

  def parse(entry)
    entry.lines.inject({}) { |hash, line| hash.merge((parse_line(line) || {})) }
  end

  def parse_line(line)
    tag_regex.match(line) { |match| {clean(match[:tag]) => match[:value]} }
  end

  def clean(tag)
    tag.tr(":", "_").to_sym
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
  def initialize(
    info:,
    downloader:        VideoDownloader.new,
    download_record:   DownloadRecord.new)
    @id              = info[:id]
    @title           = info[:title]
    @published       = Time.parse(info[:published])
    @channel_name    = info[:channel_name]
    @downloader      = downloader
    @download_record = download_record
  end

  def new?
    published > sync_time(channel_name)
  end

  def download
    downloader.run(id)
    update_cache
  end

  private

  attr_reader :id, :published, :channel_name, :download_record, :downloader

  def sync_time(channel_name)
    download_record.read(channel_name)
  end

  def update_cache
    download_record.write(time: published, channel: channel_name, id: id)
  end
end

class DownloadRecord
  def initialize(
    dir:   "~/.config/youtube-rss/download_record")
    @dir = dir
  end

  def read(channel)
    return one_week_ago if !record_exist?(channel)
    Time.parse(JSON.parse(File.read(path(channel)))["time"])
  end

  def write(time:, channel:, id:)
    File.open(path(channel), "w") { |file|
      file.write(JSON.generate(time: time, id: id)) }
  end

  private

  attr_reader :dir

  def record_exist?(channel)
    File.exist?(path(channel))
  end

  def path(channel)
    File.expand_path("#{dir}/#{channel}")
  end

  def one_week_ago
    Time.now - (60 * 60 * 24 * 7)
  end
end

# Sends a message to System caller to run youtube-dl
class VideoDownloader
  def initialize(
    system_caller:   SystemCaller.new)
    @system_caller = system_caller
  end

  def run(id)
    system_caller.run("youtube-dl \"https://youtu.be/#{id}\"")
  end

  private

  attr_reader :system_caller
end

# Ensures commands are run in the proper directory
class SystemCaller
  def initialize(
    script_halter:   ScriptHalter.new,
    args:            ARGV)
    @script_halter = script_halter
    @args          = args
  end

  def run(command)
    dl_path = args[0] || "."
    Dir.chdir(File.expand_path(dl_path)) { halt("error") if !system(command) }
  end

  private

  attr_reader :script_halter, :args

  def halt(msg)
    script_halter.run(msg)
  end
end

class ScriptHalter
  def run(msg)
    puts "youtube-rss: #{msg}"
    exit
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

  def run(feed)
    if !feed.in_cache?
      updater.run(id: feed.id, type: feed.type)
    elsif feed.old?
      updater.run(id: feed.id, type: feed.type)
    elsif feed.empty?
      updater.run(id: feed.id, type: feed.type)
    end
    read_feed(feed.id)
  end

  private

  attr_reader :updater, :reader, :dir

  def read_feed(id)
    reader.run(id)
  end
end

class FeedCacheReader
  def initialize(dir: "~/.config/youtube-rss/feed-cache")
    @dir = File.expand_path(dir)
  end

  def run(id)
    File.read("#{dir}/#{id}")
  end

  private

  attr_reader :dir
end

class FeedCacheUpdater
  def initialize(
    dir:          "~/.config/youtube-rss/feed-cache",
    downloader:   FeedDownloader.new)
    @dir        = File.expand_path(dir)
    @downloader = downloader
  end

  def run(id:, type:)
    File.open("#{dir}/#{id}", "w") do |file|
      file.write(new_feed(
        id:   id,
        type: type))
    end
  end

  private

  attr_reader :dir, :downloader

  def new_feed(args)
    downloader.run(args)
  end
end

class FeedDownloader
  def initialize(
    page_downloader:   PageDownloader.new,
    url_maker:         URLMaker.new)
    @page_downloader = page_downloader
    @url_maker       = url_maker
  end

  def run(id:, type:)
    puts "DOWNLOADING FEED #{id}"
    page(url(id: id, type: type))
  end

  private

  attr_reader :url_maker, :page_downloader

  def page(url)
    page_downloader.run(url)
  end

  def url(args)
    url_maker.run(args)
  end
end
