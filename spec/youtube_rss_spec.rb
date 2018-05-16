require "youtube_rss"

describe Main do
  let(:channel_list) { instance_double("ChannelList") }
  let(:main)         { described_class.new(channel_list: channel_list) }

  describe "#run" do
    it "tells the channel list to sync" do
      expect(channel_list).to receive(:sync)
      main.run
    end
  end
end

describe Feed do
  let(:id)      { "some_id" }
  let(:type)    { "some_type" }
  let(:comment) { "some comment" }
  let(:info)    { "#{type}/#{id} # #{comment}" }
  let(:feed)    { described_class.new(info: info) }

  specify { expect(feed.id).to eql(id) }
  specify { expect(feed.type).to eql(type) }
  specify { expect(feed.comment).to eql(comment) }
end

describe FeedList do
  let(:feed_class) { class_double("Feed") }
  let(:fake_list)  { Array.new(5, :some_feed) }
  let(:feed_list)  { described_class.new(feed_class: feed_class) }

  describe "#list" do
    it "is a list of feeds" do
      expect(File).to receive(:readlines).and_return(fake_list)
      expect(feed_class).to receive(:new).exactly(fake_list.length).times
      feed_list.list
    end
  end
end

describe ChannelFactory do
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

  let(:entry_parser)  { instance_double("EntryParser", run: entries) }
  let(:video_factory) { instance_double("VideoFactory", build: :test_video) }
  let(:channel_class) { class_double("Class") }
  let(:name)          { "jackisanerd" }
  let(:channel_args)  { {name: name, video_list: [:test_video, :test_video]} }
  let(:input)         { :some_input }

  let(:channel_factory) do
    described_class.new(
      entry_parser:  entry_parser,
      video_factory: video_factory,
      channel_class: channel_class)
  end

  describe "#build" do
    it "builds a channel object" do
      expect(entry_parser).to receive(:run).with(input)
      expect(video_factory).to receive(:build).exactly(2).times
      expect(channel_class).to receive(:new).with(channel_args)
      channel_factory.build(input)
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
      feed_list:    ["user/testuser1", "user/testuser2"])
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
  let(:id)              { "some_id" }
  let(:new_id_format)   { "channel_id=#{id}" }
  let(:old_name_format) { "user=#{id}" }

  describe "#run" do
    context "with the old username type" do
      it "returns a proper user feed url" do
        url = URI(url_start + old_name_format).to_s
        expect(described_class.new.run(id: id, type: "user").to_s).to eql(url)
      end
    end

    context "with the new channel id type" do
      it "returns a proper id feed url" do
        url = URI(url_start + new_id_format).to_s
        expect(described_class.new.run(id: id, type: "channel").to_s).
          to eql(url)
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
  let(:system_caller_double) { double("a system caller") }

  let(:downloader) do
    described_class.new(system_caller: system_caller_double)
  end

  describe "#run" do
    context "given a valid youtube id" do
      it "downloads the video" do
        id = "testid"
        expect(system_caller_double).to receive(:run).
          with("youtube-dl \"https://youtu.be/#{id}\"")
        downloader.run(id)
      end
    end
  end
end

describe SystemCaller do
  describe "#run" do
    let(:script_halter_double) { double("a script halter") }
    let(:id)                   { "some id" }
    let(:command)              { "this is a command" }
    let(:error_msg)            { "error" }
    let(:args)                 { [] }

    let(:system_caller) do
      described_class.new(
        script_halter: script_halter_double,
        args:          args)
    end

    context "the command exits without an error" do
      it "downloads the video" do
        expect(system_caller).to receive(:system).with(command).
          and_return(true)
        system_caller.run(command)
      end
    end

    context "the command exits with an error" do
      it "halts the script" do
        expect(system_caller).to receive(:system).with(command).
          and_return(false)
        expect(script_halter_double).to receive(:run).with(error_msg)
        system_caller.run(command)
      end
    end
  end
end

describe ScriptHalter do
  describe "#run" do
    let(:error_msg)     { "this is an error" }
    let(:expected_puts) { "youtube-rss: #{error_msg}" }
    let(:script_halter) { described_class.new }

    it "prints the error message and halts the script" do
      expect(script_halter).to receive(:puts).with(expected_puts)
      expect(script_halter).to receive(:exit)
      script_halter.run(error_msg)
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
  let(:http_dbl)        { double("HTTP") }
  let(:page_downloader) { described_class.new(http: http_dbl) }
  let(:url)           { "some url" }

  describe "#run" do
    it "downloads the page" do
      expect(http_dbl).to receive(:get).with(url)
      page_downloader.run(url)
    end
  end
end

describe FeedCache do
  let(:updater_double)  { double("a feed cache updater") }
  let(:reader_double)   { double("a feed cache reader") }
  let(:dir)             { "spec/fixtures/files/" }
  let(:existing_id)     { "videos.xml" }
  let(:old_time)        { Time.now - (13 * 3600) }
  let(:new_id)          { "an_id" }
  let(:feed_double)     { double("a feed") }

  let(:feed_cache) do
    described_class.new(
      updater: updater_double,
      reader:  reader_double,
      dir:     dir)
  end

  describe "#run" do
    context "when there is no cached feed" do
      it "updates the cache, returns the new feed" do
        allow(feed_double).to receive(:id).and_return(new_id)
        allow(feed_double).to receive(:type).and_return(:some_type)
        expect(updater_double).to receive(:run).
          with(id: new_id, type: :some_type)
        expect(reader_double).to receive(:run).and_return(:the_feed)
        expect(feed_cache.run(feed_double)).to eql(:the_feed)
      end
    end

    context "when the file is not old or empty" do
      it "returns that feed" do
        allow(feed_double).to receive(:id).and_return(existing_id)
        allow(feed_double).to receive(:type).and_return(:some_type)
        expect(File).to receive(:mtime).and_return(Time.now)
        expect(reader_double).to receive(:run).and_return(:the_feed)
        expect(feed_cache.run(feed_double)).to eql(:the_feed)
      end
    end

    context "when the file is old" do
      it "overwrites that file with a new download, and returns its content" do
        allow(feed_double).to receive(:id).and_return(existing_id)
        allow(feed_double).to receive(:type).and_return(:some_type)
        expect(File).to receive(:mtime).and_return(old_time)
        expect(updater_double).to receive(:run).
          with(id: existing_id, type: :some_type)
        expect(reader_double).to receive(:run).and_return(:the_feed)
        expect(feed_cache.run(feed_double)).to eql(:the_feed)
      end
    end

    context "when the file is empty" do
      it "overwrites that file with a new download, and returns its content" do
        allow(feed_double).to receive(:id).and_return(existing_id)
        allow(feed_double).to receive(:type).and_return(:some_type)
        expect(File).to receive(:mtime).and_return(Time.now)
        expect(File).to receive(:zero?).and_return(true)
        expect(updater_double).to receive(:run).
          with(id: existing_id, type: :some_type)
        expect(reader_double).to receive(:run).and_return(:the_feed)
        expect(feed_cache.run(feed_double)).to eql(:the_feed)
      end
    end
  end
end

describe FeedCacheReader do
  let(:id)                { "an_id" }
  let(:feed)              { :the_feed }
  let(:dir)               { "testdir/testsubdir" }
  let(:expected_path)     { File.expand_path("#{dir}/#{id}") }
  let(:feed_cache_reader) { described_class.new(dir: dir) }

  describe "#run" do
    it "returns the contents of the cached feed" do
      expect(File).to receive(:read).with(expected_path).and_return(feed)
      expect(feed_cache_reader.run(id)).to eql(feed)
    end
  end
end

describe FeedCacheUpdater do
  let(:downloader_double) { double("Feed Downloader") }
  let(:file_double)       { double("a file object") }
  let(:id)                { "an_id" }
  let(:type)              { "a_type" }
  let(:dir)               { "testdir/testsubdir" }
  let(:expected_path)     { File.expand_path("#{dir}/#{id}") }
  let(:new_feed)          { :new_feed }

  let(:feed_cache_updater) do
    described_class.new(
      dir:        dir,
      downloader: downloader_double)
  end

  describe "#run" do
    it "downloads a new feed and writes it to the cache" do
      expect(downloader_double).to receive(:run).
        with(id: id, type: type).
        and_return(new_feed)
      expect(File).to receive(:open).with(expected_path, "w").
        and_yield(file_double)
      expect(file_double).to receive(:write).with(new_feed)
      feed_cache_updater.run(id: id, type: type)
    end
  end
end

describe FeedDownloader do
  let(:id)                     { :the_id }
  let(:type)                   { :the_type }
  let(:url)                    { :some_url }
  let(:feed)                   { :the_feed }
  let(:url_maker_double)       { double("URLMaker") }
  let(:page_downloader_double) { double("PageDownloader") }

  let(:feed_downloader) do
    described_class.new(
      page_downloader: page_downloader_double,
      url_maker:       url_maker_double)
  end

  describe "#run" do
    it "tells the page downloader to download the feed" do
      expect(url_maker_double).to receive(:run).
        with(id: id, type: type).
        and_return(url)
      expect(page_downloader_double).to receive(:run).with(url).and_return(feed)
      expect(feed_downloader).to receive(:puts).with("DOWNLOADING FEED #{id}")
      expect(feed_downloader.run(id: id, type: type)).to eql(feed)
    end
  end
end
