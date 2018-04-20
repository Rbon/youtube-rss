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
      @url_start = "https://www.youtube.com/feeds/videos.xml?"
      @new_id_format     = "channel_id=test_id"
      @old_name_format   = "user=test_user"
    end

    context "with the old username type" do
      it "returns a proper user feed url" do
        url = URI(@url_start + @old_name_format).to_s
        expect(URLMaker.new.run("user/test_user").to_s).to eql(url)
      end
    end

    context "with the new channel id type" do
      it "returns a proper id feed url" do
        url = URI(@url_start + @new_id_format).to_s
        expect(URLMaker.new.run("channel/test_id").to_s).to eql(url)
      end
    end
  end
end

describe VideoFactory do
  describe "#build" do
    before do
      @video_factory = VideoFactory.new
      @entry = {
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
    end

    it "builds a youtube object" do
      video = @video_factory.build(@entry)
      expect(video.title).to eql("Day 4")
      expect(video.id).to eql("Ah6xjqA0Cj0")
      expect(video.channel_name).to eql("jackisanerd")
      expect(video.published).to eql(Time.parse("2018-03-03T05:59:29+00:00"))
    end
  end
end

describe Video do
  before do
    @cache_dbl      = double("Cache")
    @downloader_dbl = double("Video Downloader")
    @id = "testid"
    @time = "2000-01-01"
    @channel_name = "test channel name"
    @video = Video.new(
      id:           @id,
      channel_name: @channel_name,
      title:        "a test video",
      cache:        @cache_dbl,
      downloader:   @downloader_dbl,
      published:    @time)
  end

  describe "#new?" do
    context "when video is new" do
      it "returns true" do
        expect(@cache_dbl).to receive(:sync_time).
          and_return(Time.parse("1999-01-01"))
        expect(@video.new?).to be true
      end
    end

    context "when video is old" do
      it "returns false" do
        expect(@cache_dbl).to receive(:sync_time).
          and_return(Time.parse("2008-01-01"))
        expect(@video.new?).to be false
      end
    end
  end

  describe "#download" do
    it "downloads a video" do
      expect(@downloader_dbl).to receive(:run).with(@id)
      expect(@cache_dbl).to receive(:update).
        with(time: Time.parse(@time), channel_name: @channel_name)
      @video.download
    end
  end
end

describe ChannelFactory do
  describe "#build" do
    before do
      @entry_parser_dbl  = double("Entry Parser")
      @video_factory_dbl = double("Video Factory")
      @channel_class_dbl = double("Channel Class")
      @name = "jackisanerd"
      @entries = [
        {
           id:           "yt:channel:UCTjqo_3046IXFFGZ_M5jedA",
           name:         @name,
           published:    "2011-04-20T07:27:32+00:00",
           title:        "jackisanerd",
           yt_channelId: "UCTjqo_3046IXFFGZ_M5jedA",
           uri: "https://www.youtube.com/channel/UCTjqo_3046IXFFGZ_M5jedA"},
        :video_entry1,
        :video_entry2]
      @channel_factory   = ChannelFactory.new(
        entry_parser: @entry_parser_dbl,
        video_factory: @video_factory_dbl,
        channel_class: @channel_class_dbl)
    end
    it "builds a channel object" do
      expect(@entry_parser_dbl).to receive(:run).and_return(@entries)
      expect(@video_factory_dbl).to receive(:build).
        and_return(:test_video).
        exactly(2).times
      expect(@channel_class_dbl).to receive(:new).
        with({name: @name, video_list: [:test_video, :test_video]})
      @channel_factory.build(:test)
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

describe PageDownloader do
  describe "#run" do
    before do
      @url_maker_dbl = double("URL Maker")
      @http_dbl = double("HTTP")
      @page_downloader = PageDownloader.new(
        url_maker: @url_maker_dbl,
        http: @http_dbl)
    end

    it "downloads the page" do
      expect(@url_maker_dbl).to receive(:run).and_return(:page)
      expect(@http_dbl).to receive(:get).with(:page)
      page = @page_downloader.run(:test)
    end
  end
end
