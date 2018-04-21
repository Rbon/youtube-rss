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
  describe "#sync" do
    before do
      @video_dbl = double("Video")
      @channel = Channel.new(
        name: "test channel",
        video_list: [@video_dbl, @video_dbl])
    end
    it "downloads all the new videos" do
      expect(@video_dbl).to receive(:new?).exactly(2).times
      expect(@channel).to receive(:puts).with("test channel")
      @channel.sync
    end
  end
end

describe ChannelList do
  describe "#sync" do
    before do
      @channel_dbl = double("Channel")
      @channel_factory_dbl = double("Channel Factory")
      @channel_list = ChannelList.new(
        channel_factory: @channel_factory_dbl,
        channel_list: ["user/testuser1", "user/testuser2"])
    end

    it "tells each channel to sync" do
      expect(@channel_factory_dbl).to receive(:build).
        exactly(2).times.
        and_return(@channel_dbl)
      expect(@channel_dbl).to receive(:sync).exactly(2).times
      @channel_list.sync
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
      @video_class_dbl = double("Video Class")
      @video_factory = VideoFactory.new(video_class: @video_class_dbl)
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
      @video_info = {
        id: "Ah6xjqA0Cj0", title: "Day 4",
        published: "2018-03-03T05:59:29+00:00", channel_name: "jackisanerd"}
    end

    it "builds a youtube object" do
      expect(@video_class_dbl).to receive(:new).with(info: @video_info)
      @video_factory.build(@entry)
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
    info = {
      id:           @id,
      channel_name: @channel_name,
      title:        "a test video",
      published:    @time}
    @video = Video.new(
      cache:        @cache_dbl,
      downloader:   @downloader_dbl,
      info: info)
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
  before do
    @downloader = VideoDownloader.new
  end

  describe "#run" do
    context "given a valid youtube id" do
      it "downloads the video" do
        id = "testid"
        expect(SystemCaller).to receive(:run).
          with("youtube-dl \"https://youtu.be/#{id}\"")
        @downloader.run(id)
      end
    end
  end
end

describe SystemCaller do
  describe ".run" do
    it "downloads the video" do
      ARGV[0] = nil # this is a hack
      command = "this is a command"
      expect(SystemCaller).to receive(:system).
        with(command)
      SystemCaller.run(command)
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
      expect(@page_downloader).to receive(:puts).
       with("DOWNLOADING FEED #{:test}")
      expect(@url_maker_dbl).to receive(:run).and_return(:page)
      expect(@http_dbl).to receive(:get).with(:page)
      page = @page_downloader.run(:test)
    end
  end
end

describe FeedFinder do
  describe "#run" do
    before do
      @page_dlr_dbl = double("Page Downloader")
      @file_obj_dbl = double("File Object")
      @file_dbl     = double("File")
      @test_feed    = File.read("spec/fixtures/files/videos.xml")
      @old_time     = Time.now - (13 * 3600)
    end

    context "when there is no cached feed" do
      it "saves a new feed to the cache, reads it, and returns its content" do
        feed_getter = FeedFinder.new(
          page_downloader: @page_dlr_dbl,
          path:            "testpath/%s",
          file:            @file_dbl)
        allow(@file_dbl).to receive(:expand_path).
          and_return(:path_of_file)
        expect(@file_dbl).to receive(:file?).and_return(false)
        expect(@file_dbl).to receive(:open).
          with(:path_of_file, "w").
          and_yield(@file_obj_dbl)
        expect(@page_dlr_dbl).to receive(:run).with("user/videos.xml").
          and_return(:result)
        expect(@file_obj_dbl).to receive(:write).with(:result)
        expect(@file_dbl).to receive(:read).
          with(:path_of_file).
          and_return(:the_file)
        feed = feed_getter.run("user/videos.xml")
        expect(feed).to eql(:the_file)
      end
    end

    context "when there is an up to date cached feed" do
      it "reads that file and returns its content" do
        feed_getter = FeedFinder.new(
          page_downloader: @page_dlr_dbl,
          path:            "testpath/%s",
          file:            @file_dbl)
        allow(@file_dbl).to receive(:expand_path).
          and_return(:path_of_file)
        expect(@file_dbl).to receive(:zero?).
          with(:path_of_file).
          and_return(false)
        expect(@file_dbl).to receive(:file?).and_return(true)
        expect(@file_dbl).to receive(:mtime).and_return(Time.now)
        expect(@file_dbl).to receive(:read).
          with(:path_of_file).
          and_return(:the_file)
        feed = feed_getter.run("user/videos.xml")
        expect(feed).to eql(:the_file)
      end
    end

    context "when the file in cache is old" do
      it "overwrites that file with a new download, and returns its content" do
        feed_getter = FeedFinder.new(
          page_downloader: @page_dlr_dbl,
          path:            "testpath/%s",
          file:            @file_dbl)
        allow(@file_dbl).to receive(:expand_path).
          and_return(:path_of_file)
        expect(@file_dbl).to receive(:file?).and_return(true)
        expect(@file_dbl).to receive(:mtime).and_return(@old_time)
        expect(@file_dbl).to receive(:open).
          with(:path_of_file, "w").
          and_yield(@file_obj_dbl)
        expect(@page_dlr_dbl).to receive(:run).with("user/videos.xml").
          and_return(:result)
        expect(@file_obj_dbl).to receive(:write).with(:result)
        expect(@file_dbl).to receive(:read).
          with(:path_of_file).
          and_return(:the_file)
        feed = feed_getter.run("user/videos.xml")
        expect(feed).to eql(:the_file)
      end
    end

    context "when the file exists and is new, but is empty" do
      it "overwrites that file with a new download, and returns its content" do
        feed_getter = FeedFinder.new(
          page_downloader: @page_dlr_dbl,
          path:            "testpath/%s",
          file:            @file_dbl)
        allow(@file_dbl).to receive(:expand_path).
          and_return(:path_of_file)
        expect(@file_dbl).to receive(:file?).and_return(true)
        expect(@file_dbl).to receive(:mtime).and_return(Time.now)
        expect(@file_dbl).to receive(:zero?).
          with(:path_of_file).
          and_return(true)
        expect(@file_dbl).to receive(:open).
          with(:path_of_file, "w").
          and_yield(@file_obj_dbl)
        expect(@page_dlr_dbl).to receive(:run).with("user/videos.xml").
          and_return(:result)
        expect(@file_obj_dbl).to receive(:write).with(:result)
        expect(@file_dbl).to receive(:read).
          with(:path_of_file).
          and_return(:the_file)
        feed = feed_getter.run("user/videos.xml")
        expect(feed).to eql(:the_file)
      end
    end
  end
end
