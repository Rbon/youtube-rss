require "youtube_rss"

describe Main do
  describe "#run" do
    it "tells the channel list to sync" do
      # feed = File.read("spec/fixtures/files/videos.xml")
      channel_list_dbl = double("Channel List")
      expect(channel_list_dbl).to receive(:sync)
      Main.new(channel_list: channel_list_dbl).run
    end
  end
end

describe ChannelList do
  describe "#sync" do
    it "tells each channel to sync" do
      channel_dbl = double("Channel")
      expect(channel_dbl).to receive(:sync).exactly(2).times
      channel_factory_dbl = double("Channel Factory")
      expect(channel_factory_dbl).to receive(:for).
        exactly(2).times.
        and_return(channel_dbl)
      ChannelList.new(
        channel_factory: channel_factory_dbl,
        channel_list: ["user/testuser1", "user/testuser2"]).sync
    end
  end
end

describe URLMaker do
  describe "#run" do
    before do
      @id = "test_id"
      @fake_page = File.read("spec/fixtures/files/videos.xml")
    end

    context "with the old channel name type" do
      it "returns a proper feed url" do
        url = "user/#{@id}"
        expect(URLMaker.new.run(url)).
          to eql("https://www.youtube.com/feeds/videos.xml?user=test_id")
      end
    end

    context "with the new channel id type" do
      it "returns a proper feed url" do
        url = "channel/#{@id}"
        expect(URLMaker.new.run(url)).
          to eql("https://www.youtube.com/feeds/videos.xml?channel_id=test_id")
      end
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
        with(id)
      video.download
    end
  end
end

describe Channel do
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
      expect(File).to receive(:open).and_return(file_dbl)
      Cache.update(time: @time, channel_name: @channel_name)
    end

    context "when the channel name already exists in the cache" do
      it "updates the cache file" do
        fake_json = "\"foo\": \"1\", \"#{@channel_name}\": \"#{@time}\""
        fake_parsed_json = {"foo" => "1", @channel_name => @time}
        expect(File).to receive(:read).and_return("{#{fake_json}}")
        file_dbl = double("File")
        expect(File).to receive(:open).and_return(file_dbl)
        Cache.update(time: @time, channel_name: @channel_name)
      end
    end
  end
end

describe VideoDownloader do
  describe ".run" do
    it "downloads the video" do
      ARGV[0] = nil # this is a hack
      id = "testid"
      downloader = VideoDownloader.new
      expect(downloader).to receive(:system).
        with("youtube-dl #{id}")
      downloader.run(id)
    end
  end
end

describe EntryParser do
  describe "#run" do
    before do
      @page = File.read("spec/fixtures/files/videos.xml")
      @channel_entry = {
        id:           "yt:channel:UCTjqo_3046IXFFGZ_M5jedA",
        name:         "jackisanerd",
        published:    "2011-04-20T07:27:32+00:00",
        title:        "jackisanerd",
        yt_channelId: "UCTjqo_3046IXFFGZ_M5jedA",
        uri: "https://www.youtube.com/channel/UCTjqo_3046IXFFGZ_M5jedA"}
      @video_entry = {
        id:                "yt:video:Ah6xjqA0Cj0",
        media_description: "Not the best day but maybe tomorrow will be better",
        media_title:       "Day 4",
        name:              "jackisanerd",
        published:         "2018-03-03T05:59:29+00:00",
        title:             "Day 4",
        updated:           "2018-03-03T19:57:10+00:00",
        yt_channelId:      "UCTjqo_3046IXFFGZ_M5jedA",
        yt_videoId:        "Ah6xjqA0Cj0",
        uri: "https://www.youtube.com/channel/UCTjqo_3046IXFFGZ_M5jedA"}
      @page_drl_dbl = double("Page Downloader")
      @entry_parser = EntryParser.new(page_downloader: @page_drl_dbl)
    end

    it "returns an array of parsed entries" do
      expect(@page_drl_dbl).to receive(:run).and_return(@page)
      entries = @entry_parser.run(:test)
      expect(entries[0]).to eql(@channel_entry)
      expect(entries[1]).to eql(@video_entry)
    end
  end
end
