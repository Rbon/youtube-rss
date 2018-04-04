require "youtube-rss"

describe Main do
  describe "#run" do
    before do
      @channel_dbl = double("Channel")
      @video_dbl = double("Video")
    end

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
      dl_path = double("DL Path")
      @channel = ChannelFactory.for(
        channel_info: channel_info,
        cache_file: cache_file,
        video_info_list: video_info_list,
        dl_path: dl_path
      )
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
        channel_dbl = double("Channel")
        video = Video.new(info: @info, channel: channel_dbl, dl_path: "")
        expect(channel_dbl).to receive(:sync_time) { Time.parse("1999-01-01") }
        expect(video.new?).to be true
      end
    end

    context "when video is old" do
      it "returns false" do
        @info["published"] = "1999-01-01"
        channel_dbl = double("Channel")
        video = Video.new(info: @info, channel: channel_dbl, dl_path: "")
        expect(channel_dbl).to receive(:sync_time) { Time.parse("2000-01-01") }
        expect(video.new?).to be false
      end
    end
  end

  describe "#download" do
    it "runs the execer" do
      pub_time = "2017-03-01"
      info = {"yt:videoId" => "testid", "published" => pub_time}
      channel_dbl = double("Channel")
      expect(Dir).to receive(:chdir)
      dl_path = "test path"
      video = Video.new(
        info: info,
        channel: channel_dbl,
        dl_path: dl_path)
      expect(channel_dbl).to receive(:sync_time=)
      video.download
    end
  end
end

describe Channel do
  describe "#sync_time" do
    it "returns the time from the cache file" do
      fake_cache = '{"test channel":"2000-01-01 00:00:00 -0800"}'
      expect(File).to receive(:read).and_return(fake_cache)
      channel = Channel.new(id: "testid", name: "test channel", cache_file: "")
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
      channel = Channel.new(id: "testid", name: "test channel", cache_file: "")
      channel.sync_time = time
    end
  end
end
