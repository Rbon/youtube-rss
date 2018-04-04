#! /usr/bin/env ruby

###BUGS: If youtube-dl isn't present, the script thinks everything is fine, and
###      updates the sync dates.

require "open-uri"
require "time"
require "json"

class Main
  def initialize
    @dl_path = ARGV[0] || "."
    @channel_list = File.readlines(File.expand_path("~/.config/youtube-rss/channel_list.txt"))
  end

  def run
    @channel_list.each do |line|
      feed = FeedDownloader.download(line)
      parsed_feed = FeedParser.parse(feed)
      channel = ChannelFactory.for(
        channel_info: parsed_feed[:channel_info],
        video_info_list: parsed_feed[:video_info_list],
        dl_path: @dl_path,
        cache_file: File.expand_path("~/.config/youtube-rss/cache.json")
      )
      puts channel.name
      channel.new_videos.each(&:download)
    end
  end
end

class FeedDownloader
    FEED_TYPES = {
      channel: "https://www.youtube.com/feeds/videos.xml?channel_id=%s",
      user: "https://www.youtube.com/feeds/videos.xml?user=%s"
    }

  def self.download(url)
    url = url.split("#")[0].strip
    type, id = url.split("/")
    feed = open(FEED_TYPES[type.to_sym] % id) { |io| io.read }
    feed
  end
end

class ChannelFactory
  def self.for(channel_info:, video_info_list:, cache_file:, dl_path:)
    channel = Channel.new(
      id: channel_info["yt:channelId"],
      name: channel_info["name"],
      cache_file: cache_file
    )
    video_list = video_info_list.map { |video_info| Video.new(
      info: video_info, channel: channel, dl_path: dl_path
    ) }
    channel.video_list = video_list.reverse
    channel
  end
end

class FeedParser
  TAG_REGEX = /<(?<tag>.*)>(?<value>.*)<.*>/

  def self.parse(feed)
    feed = feed.split("<entry>")
    channel_info = make_info(feed[0])
    video_info_list = feed.drop(1).map { |entry| make_info(entry) }
    {channel_info: channel_info, video_info_list: video_info_list}
  end

  private

  def self.make_info(entry)
    info = {}
    entry.lines do |line|
      TAG_REGEX.match(line) { |match| info[match[:tag]] = match[:value] }
    end
    info
  end
end

class Channel
  attr_reader :name, :id
  attr_accessor :video_list

  def initialize(id:, name:, cache_file:)
    @id = id
    @name = name
    @video_list = []
    @cache_file = cache_file
  end

  def sync_time=(time)
    cache = File.read(@cache_file)
    cache = JSON.parse(cache)
    cache[@name] = time
    file = File.open(@cache_file, "w")
    JSON.dump(cache, file)
    file.close
  end

  def sync_time
    time = File.read(@cache_file)
    time = JSON.parse(time)[@name]
    Time.parse(time || "2018-03-01")
  end

  def new_videos
    @video_list.select(&:new?)
  end
end

class Video
  attr_reader :id, :published, :title, :description

  def initialize(info:, channel:, dl_path:)
    @id = info["yt:videoId"]
    @title = info["title"]
    @description = info["description"]
    @published = Time.parse(info["published"])
    @channel = channel
    @dl_path = dl_path
  end

  def new?
    @channel.sync_time < @published
  end

  def download
    Dir.chdir(File.expand_path(@dl_path)) { system("youtube-dl #{@id}") }
    @channel.sync_time = @published
  end
end

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
end

# Main.new.run
