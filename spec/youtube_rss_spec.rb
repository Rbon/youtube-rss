require "youtube_rss"

describe Main do
  describe "#run" do
    it "tells the channel list to sync" do
      # feed = File.read("spec/fixtures/files/videos.xml")
      channel_list_dbl = double("Channel List")
      expect(channel_list_dbl).to receive(:sync)
      described_class.new(channel_list: channel_list_dbl).run
    end
  end
end

describe ChannelFactory do
  let(:entry_parser_dbl)  { double("Entry Parser") }
  let(:video_factory_dbl) { double("Video Factory") }
  let(:channel_class_dbl) { double("Channel Class") }
  let(:name)              { "jackisanerd" }

  let(:entries) do
    [{
       id:           "yt:channel:UCTjqo_3046IXFFGZ_M5jedA",
       name:         name,
       published:    "2011-04-20T07:27:32+00:00",
       title:        "jackisanerd",
       yt_channelId: "UCTjqo_3046IXFFGZ_M5jedA",
       uri: "https://www.youtube.com/channel/UCTjqo_3046IXFFGZ_M5jedA"},
    :video_entry1,
    :video_entry2]
  end

  let(:channel_factory) do
    described_class.new(
      entry_parser:  entry_parser_dbl,
      video_factory: video_factory_dbl,
      channel_class: channel_class_dbl)
  end

  describe "#build" do
    it "builds a channel object" do
      expect(entry_parser_dbl).to receive(:run).and_return(entries)
      expect(video_factory_dbl).to receive(:build).
        and_return(:test_video).
        exactly(2).times
      expect(channel_class_dbl).to receive(:new).
        with({name: name, video_list: [:test_video, :test_video]})
      channel_factory.build(:test)
    end
  end
end

describe Channel do
  let(:video_dbl) { double("Video") }

  let(:channel) do
    described_class.new(
      name:       "test channel",
      video_list: [video_dbl, video_dbl])
  end

  describe "#sync" do
    it "downloads all the new videos" do
      expect(video_dbl).to receive(:new?).exactly(2).times
      expect(channel).to receive(:puts).with("test channel")
      channel.sync
    end
  end
end

describe ChannelList do
  let(:channel_dbl)         { double("Channel") }
  let(:channel_factory_dbl) { double("Channel Factory") }

  let(:channel_list) do
    described_class.new(
      channel_factory: channel_factory_dbl,
      channel_list:    ["user/testuser1", "user/testuser2"])
  end

  describe "#sync" do
    it "tells each channel to sync" do
      expect(channel_factory_dbl).to receive(:build).
        exactly(2).times.
        and_return(channel_dbl)
      expect(channel_dbl).to receive(:sync).exactly(2).times
      channel_list.sync
    end
  end
end

describe URLMaker do
  let(:url_start)       { "https://www.youtube.com/feeds/videos.xml?" }
  let(:new_id_format)   { "channel_id=test_id" }
  let(:old_name_format) { "user=test_user" }

  describe "#run" do
    context "with the old username type" do
      it "returns a proper user feed url" do
        url = URI(url_start + old_name_format).to_s
        expect(described_class.new.run("user/test_user").to_s).to eql(url)
      end
    end

    context "with the new channel id type" do
      it "returns a proper id feed url" do
        url = URI(url_start + new_id_format).to_s
        expect(described_class.new.run("channel/test_id").to_s).to eql(url)
      end
    end
  end
end

describe VideoFactory do
  let(:video_class_dbl) { double("Video Class") }
  let(:video_factory)   { described_class.new(video_class: video_class_dbl) }

  let(:entry) do
    {id:                "yt:video:Ah6xjqA0Cj0",
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

  let(:video_info) do
    {id:           "Ah6xjqA0Cj0",
     title:        "Day 4",
     published:    "2018-03-03T05:59:29+00:00",
     channel_name: "jackisanerd"}
  end

  describe "#build" do
    it "builds a youtube object" do
      expect(video_class_dbl).to receive(:new).with(info: video_info)
      video_factory.build(entry)
    end
  end
end

describe Video do
  let(:cache_dbl)      { double("Cache") }
  let(:downloader_dbl) { double("Video Downloader") }
  let(:id)             { "testid" }
  let(:time)           { "2000-01-01" }
  let(:channel_name)   { "test channel name" }

  let(:info) do
    {id:           id,
     channel_name: channel_name,
     title:        "a test video",
     published:    time}
  end

  let(:video) do
    described_class.new(
      cache:      cache_dbl,
      downloader: downloader_dbl,
      info:       info)
  end

  describe "#new?" do
    context "when video is new" do
      it "returns true" do
        expect(cache_dbl).to receive(:sync_time).
          and_return(Time.parse("1999-01-01"))
        expect(video.new?).to be true
      end
    end

    context "when video is old" do
      it "returns false" do
        expect(cache_dbl).to receive(:sync_time).
          and_return(Time.parse("2008-01-01"))
        expect(video.new?).to be false
      end
    end
  end

  describe "#download" do
    it "downloads a video" do
      expect(downloader_dbl).to receive(:run).with(id)
      expect(cache_dbl).to receive(:update).
        with(time: Time.parse(time), channel_name: channel_name)
      video.download
    end
  end
end


describe Cache do
  let(:time)         { "some time" }
  let(:channel_name) { "test channel" }

  describe ".update" do
    context "when the channel name doesn't already exist in cache"
    it "updates the cache file" do
      fake_json = "\"foo\": \"1\", \"bar\": \"2\""
      fake_parsed_json = {"foo" => "1", "bar" => "2", channel_name => time}
      expect(File).to receive(:read).and_return("{#{fake_json}}")
      file_dbl = double("File")
      expect(File).to receive(:open).and_return(file_dbl)
      Cache.update(time: time, channel_name: channel_name)
    end

    context "when the channel name already exists in the cache" do
      it "updates the cache file" do
        fake_json = "\"foo\": \"1\", \"#{channel_name}\": \"#{time}\""
        fake_parsed_json = {"foo" => "1", channel_name => time}
        expect(File).to receive(:read).and_return("{#{fake_json}}")
        file_dbl = double("File")
        expect(File).to receive(:open).and_return(file_dbl)
        Cache.update(time: time, channel_name: channel_name)
      end
    end
  end
end

describe VideoDownloader do
  let(:downloader) { described_class.new }

  describe "#run" do
    context "given a valid youtube id" do
      it "downloads the video" do
        id = "testid"
        expect(SystemCaller).to receive(:run).
          with("youtube-dl \"https://youtu.be/#{id}\"")
        downloader.run(id)
      end
    end
  end
end

describe SystemCaller do
  describe ".run" do
    it "downloads the video" do
      ARGV[0] = nil # this is a hack
      command = "this is a command"
      expect(described_class).to receive(:system).
        with(command)
      described_class.run(command)
    end
  end
end

describe EntryParser do
  let(:page)         { File.read("spec/fixtures/files/videos.xml") }
  let(:page_drl_dbl) { double("Page Downloader") }
  let(:entry_parser) { described_class.new(page_downloader: page_drl_dbl) }

  let(:channel_entry) do
    {id:           "yt:channel:UCTjqo_3046IXFFGZ_M5jedA",
     name:         "jackisanerd",
     published:    "2011-04-20T07:27:32+00:00",
     title:        "jackisanerd",
     yt_channelId: "UCTjqo_3046IXFFGZ_M5jedA",
     uri: "https://www.youtube.com/channel/UCTjqo_3046IXFFGZ_M5jedA"}
  end

  let(:video_entry) do
    {id:                "yt:video:Ah6xjqA0Cj0",
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

  describe "#run" do
    it "returns an array of parsed entries" do
      expect(page_drl_dbl).to receive(:run).and_return(page)
      entries = entry_parser.run(:test)
      expect(entries[0]).to eql(channel_entry)
      expect(entries[1]).to eql(video_entry)
    end
  end
end

describe PageDownloader do
  let(:url_maker_dbl) { double("URL Maker") }
  let(:http_dbl)      { double("HTTP") }

  let(:page_downloader) do
    described_class.new(
      url_maker: url_maker_dbl,
      http:      http_dbl)
  end

  describe "#run" do
    it "downloads the page" do
      expect(page_downloader).to receive(:puts).
       with("DOWNLOADING FEED #{:test}")
      expect(url_maker_dbl).to receive(:run).and_return(:page)
      expect(http_dbl).to receive(:get).with(:page)
      page_downloader.run(:test)
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
