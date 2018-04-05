require "youtube-rss"

describe Main do
  describe "#run" do
    before do
      @channel_dbl = double("Channel")
      @video_dbl = double("Video")
    end

    # this should be much better
    it "runs the script" do
      expect(File).to receive(:readlines).and_return(["test"])
      main = Main.new

      expect(FeedDownloader).to receive(:download)
      expect(FeedParser).to receive(:parse).
        and_return({channel_info: nil, video_info_list: nil})
      expect(ChannelFactory).to receive(:for).
        and_return(@channel_dbl)
      expect(@channel_dbl).to receive(:name).
        and_return("test channel")
      expect(@channel_dbl).to receive(:new_videos).
        and_return([@video_dbl])
      expect(@video_dbl).to receive(:download)
      expect(main).to receive(:puts)
      main.run
    end
  end
end

describe FeedDownloader do
  describe ".download" do
    before do
      @id = "test_id"
      @fake_page = File.read("spec/fixtures/files/videos.xml")
    end

    context "with the old channel name type" do
      it "returns a proper feed url" do
        url = "user/#{@id}"
        expect(FeedDownloader).to receive(:open).
          with("https://www.youtube.com/feeds/videos.xml?user=#{@id}").
          and_return(@fake_page)
        expect(FeedDownloader.download(url)).to eql(@fake_page)
      end
    end

    context "returns a proper feed url" do
      it "returns a feed" do
        url = "channel/#{@id}"
        expect(FeedDownloader).to receive(:open).
          with("https://www.youtube.com/feeds/videos.xml?channel_id=#{@id}").
          and_return(@fake_page)
        expect(FeedDownloader.download(url)).to eql(@fake_page)
      end
    end
  end
end

describe FeedParser do
  describe ".parse" do
    before do
      @feed = File.read("spec/fixtures/files/videos.xml")
      @parsed_feed = FeedParser.parse(@feed)
    end

    it "returns a hash with channel info" do
      channel_info = @parsed_feed[:channel_info]
      expect(channel_info["name"]).to eql("jackisanerd")
      expect(channel_info["yt:channelId"]).to eql("UCTjqo_3046IXFFGZ_M5jedA")
    end

    it "returns a hash with video info" do
      video_entry = @parsed_feed[:video_info_list][0]
      expect(video_entry["title"]).to eql("Day 4")
      expect(video_entry["yt:videoId"]).to eql("Ah6xjqA0Cj0")
      expect(video_entry["published"]).to eql("2018-03-03T05:59:29+00:00")
    end
  end
end

describe ChannelFactory do
  describe ".for" do
    before do
      channel_info = {"yt:channelId" => "test chanid", "name" => "test channel"}
      video_info_list = [
        {
          "title" => "test video 2", "yt:videoId" => "test videoid 2",
          "published" => "2008-01-01", "description" => "desc1"
        },
        {
          "title" => "test video 1", "yt:videoId" => "test videoid 1",
          "published" => "1999-01-01", "description" => "desc2"
        }
      ]
      cache_file = double("Cache File")
      @channel = ChannelFactory.for(
        channel_info: channel_info,
        video_info_list: video_info_list)
    end

    it "returns a channel object" do
      expect(@channel.name).to eql("test channel")
      expect(@channel.id).to eql("test chanid")
    end

    it "returns a channel object with a list of videos" do
      expect(@channel.video_list.length).to eql(2)
      video = @channel.video_list[0]
      expect(video.title).to eql("test video 1")
      expect(video.id).to eql("test videoid 1")
    end
  end
end

describe Video do
  describe "#new?" do
    before(:all) do
      @info = {"yt:videoId" => "test video"}
    end

    context "when video is new" do
      it "returns true" do
        @info["published"] = "2000-01-01"
        video = Video.new(info: @info, channel_name: "")
        expect(Cache).to receive(:sync_time) { Time.parse("1999-01-01") }
        expect(video.new?).to be true
      end
    end

    context "when video is old" do
      it "returns false" do
        @info["published"] = "1999-01-01"
        video = Video.new(info: @info, channel_name: "")
        expect(Cache).to receive(:sync_time) { Time.parse("2000-01-01") }
        expect(video.new?).to be false
      end
    end
  end

  describe "#download" do
    it "downloads a video" do
      id = "testid"
      pub_time = "2017-03-01"
      info = {"yt:videoId" => id, "published" => pub_time}
      downloader_dbl = double("Downloader")
      expect(Cache).to receive(:update)
      video = Video.new(
        info: info,
        channel_name: nil,
        downloader: downloader_dbl)
      expect(downloader_dbl).to receive(:run).
        with(id: id)
      video.download
    end
  end
end

describe Channel do
  describe "#sync_time" do
    it "returns the time from the cache file" do
      fake_cache = '{"test channel":"2000-01-01 00:00:00 -0800"}'
      expect(File).to receive(:read).and_return(fake_cache)
      channel = Channel.new(id: "testid", name: "test channel", video_list: "")
      expect(channel.sync_time.to_s).to eql("2000-01-01 00:00:00 -0800")
    end
  end

  describe "#sync_time=" do
    it "updates the cache file" do
      fake_cache = '{"test channel":"2000-01-01 00:00:00 -0800"}'
      cache_dbl = double("Cache")
      time = "a time"
      expect(File).to receive(:read).and_return(fake_cache)
      expect(File).to receive(:open).and_return(cache_dbl)
      expect(JSON).to receive(:dump).with(
        {"test channel" => "a time"}, cache_dbl)
      expect(cache_dbl).to receive(:close)
      channel = Channel.new(id: "testid", name: "test channel", video_list: "")
      channel.sync_time = time
    end
  end
end

describe Cache do
  before do
    @time = "some time"
    @channel_name = "test channel"
  end

  describe ".update" do
    context "when the channel name doesn't already exist in cache"
    it "updates the cache file" do
      fake_json = "\"foo\": \"1\", \"bar\": \"2\""
      fake_parsed_json = {"foo" => "1", "bar" => "2", @channel_name => @time}
      expect(File).to receive(:read).and_return("{#{fake_json}}")
      file_dbl = double("File")
      expect(file_dbl).to receive(:close)
      expect(File).to receive(:open).and_return(file_dbl)
      expect(JSON).to receive(:dump).
        with(fake_parsed_json, anything)
      Cache.update(time: @time, channel_name: @channel_name)
    end

    context "when the channel name already exists in the cache" do
      it "updates the cache file" do
        fake_json = "\"foo\": \"1\", \"#{@channel_name}\": \"#{@time}\""
        fake_parsed_json = {"foo" => "1", @channel_name => @time}
        expect(File).to receive(:read).and_return("{#{fake_json}}")
        file_dbl = double("File")
        expect(file_dbl).to receive(:close)
        expect(File).to receive(:open).and_return(file_dbl)
        expect(JSON).to receive(:dump).
          with(fake_parsed_json, anything)
        Cache.update(time: @time, channel_name: @channel_name)
      end
    end
  end
end

describe Downloader do
  describe ".run" do
    it "downloads the video" do
      id = "testid"
      downloader = Downloader.new
      expect(downloader).to receive(:system).
        with("youtube-dl #{id}")
      downloader.run(id: id)
    end
  end
end
