require "youtube_rss"

describe Main do
  let(:feed_list)    { instance_double("FeedList") }

  let(:main) do described_class.new(
    feed_list:    feed_list)
  end

  describe "#run" do
    it "syncs the feeds and syncs the channels" do
      expect(feed_list).to receive(:sync)
      main.run
    end
  end
end

describe Feed do
  let(:existing_id)   { "videos.xml" }
  let(:new_id)        { "some_bad_id" }
  let(:empty_file_id) { "empty_file" }
  let(:type)          { "some_type" }
  let(:comment)       { "some comment" }
  let(:dir)           { "spec/fixtures/files" }
  let(:old_time)      { Time.now - 43200 }
  let(:reader)        { instance_double("FeedCacheReader") }
  let(:updater)       { instance_double("FeedCacheUpdater") }

  let(:new_feed) do
    described_class.new(
       info:    "#{type}/#{new_id} # #{comment}",
       dir:     dir,
       reader:  reader,
       updater: updater)
  end

  let(:existing_feed) do
    described_class.new(
       info:    "#{type}/#{existing_id} # #{comment}",
       dir:     dir,
       reader:  reader,
       updater: updater)
  end

  let(:empty_feed) do
    described_class.new(
       info:    "#{type}/#{empty_file_id} # #{comment}",
       dir:     dir,
       reader:  reader,
       updater: updater)
  end

  describe "#sync" do
    context "when there is no cached feed" do
      it "updates the cache, returns the new feed" do
        expect(updater).to receive(:run).with(id: new_id, type: type)
        expect(reader).to receive(:run).and_return(:the_feed)
        new_feed.sync
        expect(new_feed.contents).to eql(:the_feed)
      end
    end

    context "when the file is not old or empty" do
      it "returns that feed" do
        expect(File).to receive(:mtime).and_return(Time.now)
        expect(reader).to receive(:run).and_return(:the_feed)
        existing_feed.sync
        expect(existing_feed.contents).to eql(:the_feed)
      end
    end

    context "when the file is old" do
      it "overwrites that file with a new download, and returns its content" do
        expect(File).to receive(:mtime).and_return(old_time)
        expect(updater).to receive(:run).with(id: existing_id, type: type)
        expect(reader).to receive(:run).and_return(:the_feed)
        existing_feed.sync
        expect(existing_feed.contents).to eql(:the_feed)
      end
    end

    context "when the file is empty" do
      it "overwrites that file with a new download, and returns its content" do
        expect(updater).to receive(:run).with(id: empty_file_id, type: type)
        expect(reader).to receive(:run).and_return(:the_feed)
        empty_feed.sync
        expect(empty_feed.contents).to eql(:the_feed)
      end
    end
  end
end

describe FeedList do
  let(:channel_list_class) { class_double("ChannelList") }
  let(:channel_list) { instance_double("ChannelList") }
  let(:feed_class) { class_double("Feed") }
  let(:feed)       { instance_double("Feed") }
  let(:fake_list)  { Array.new(5, :some_feed) }

  let(:feed_list) do
    described_class.new(
      feed_class: feed_class,
      channel_list_class: channel_list_class)
  end

  describe "#sync" do
    it "downloads any new feeds" do
      expect(File).to receive(:readlines).and_return(fake_list)
      1.upto(fake_list.length) do |step|
        expect(feed_class).to receive(:new).and_return(feed)
        expect(feed).to receive(:sync)
        expect(feed_list).to receive(:print).
          with("\rSyncing feeds [#{step}/#{fake_list.length}]")
        expect($stdout).to receive(:flush)
      end
      expect(feed_list).to receive(:print).with("\n")
      expect(channel_list_class).to receive(:new).and_return(channel_list)
      expect(channel_list).to receive(:sync)
      feed_list.sync
    end
  end
end

describe Channel do
  let(:name)              { "test channel" }
  let(:entries)           { [{name: name}, :video_entry1, :video_entry2]}
  let(:feed)              { instance_double("Feed", contents: :some_contents) }
  let(:new_video)         { instance_double("Video", new?: true) }
  let(:old_video)         { instance_double("Video", new?: false) }
  let(:new_video_factory) { instance_double("VideoFactory", build: new_video) }
  let(:old_video_factory) { instance_double("VideoFactory", build: old_video) }
  let(:entry_parser)      { instance_double("EntryParser", run: entries) }

  describe "#sync" do
    let(:channel) do
      described_class.new(
        feed:          feed,
        entry_parser:  entry_parser,
        video_factory: new_video_factory)
    end

    context "when there are new videos" do
      it "downloads all the new videos" do
        expect(entry_parser).to receive(:run)
        expect(channel).to receive(:puts).with(name)
        expect(new_video).to receive(:download).exactly(entries.length - 1).times
        channel.sync
      end
    end

    context "when there are no new videos" do
      let(:channel) do
        described_class.new(
          feed:          feed,
          entry_parser:  entry_parser,
          video_factory: old_video_factory)
      end

      it "does nothing" do
        channel.sync
      end
    end
  end
end

describe ChannelList do
  let(:channel)       { instance_double("Channel") }
  let(:channel_class) { class_double("Channel", new: channel) }
  let(:feed_list)     { ["user/testuser1", "user/testuser2"] }

  let(:channel_list) do
    described_class.new(
      channel_class: channel_class,
      feed_list:     feed_list)
  end

  describe "#sync" do
    it "tells each channel to sync" do
      expect(channel_class).to receive(:new).exactly(feed_list.length).times
      expect(channel).to receive(:sync).exactly(feed_list.length).times
      channel_list.sync
    end
  end
end

describe URLMaker do
  let(:url_start)      { "https://www.youtube.com/feeds/videos.xml?" }
  let(:id)             { "some_id" }
  let(:channel_id_url) { URI(url_start + "channel_id=#{id}") }
  let(:user_url)       { URI(url_start + "user=#{id}") }
  let(:url_maker)      { described_class.new }

  describe "#run" do
    context "with the old username type" do
      subject { url_maker.run(id: id, type: "user") }
      it { should eql(user_url) }
    end

    context "with the new channel id type" do
      subject { url_maker.run(id: id, type: "channel") }
      it { should eql(channel_id_url) }
    end
  end
end

describe VideoFactory do
  let(:video_class)   { class_double("Video") }
  let(:video_factory) { described_class.new(video_class: video_class) }

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
    it "builds a video object" do
      expect(video_class).to receive(:new).with(info: video_info)
      video_factory.build(entry)
    end
  end
end

describe Video do
  let(:download_record) { instance_double("DownloadRecord") }
  let(:downloader)      { instance_double("VideoDownloader") }
  let(:id)              { "testid" }
  let(:time)            { "2000-01-01" }
  let(:channel_name)    { "test channel name" }

  let(:download_args) do
    {time:    Time.parse(time),
     channel: channel_name,
     id:      id}
  end

  let(:info) do
    {id:           id,
     channel_name: channel_name,
     title:        "a test video",
     published:    time}
  end

  let(:video) do
    described_class.new(
      download_record: download_record,
      downloader:      downloader,
      info:            info)
  end

  describe "#new?" do
    context "when video is new" do
      it "returns true" do
        expect(download_record).to receive(:read).
          and_return(Time.parse("1999-01-01"))
        expect(video.new?).to be true
      end
    end

    context "when video is old" do
      it "returns false" do
        expect(download_record).to receive(:read).
          and_return(Time.parse("2008-01-01"))
        expect(video.new?).to be false
      end
    end
  end

  describe "#download" do
    it "downloads a video" do
      expect(downloader).to receive(:run)
      video.download
    end
  end
end

describe DownloadRecord do
  let(:file)            { double("some file") }
  let(:time)            { Time.parse("2001-04-05")}
  let(:id)              { "the id" }
  let(:record_data)     { JSON.generate(time: time, id: id) }
  let(:dir)             { "testpath" }
  let(:channel)         { "the_channel" }
  let(:path)            { File.expand_path("#{dir}/#{channel}") }
  let(:file_args)       { [path, "w"] }
  let(:download_record) { described_class.new(dir: dir) }
  let(:old_time)        { (Time.now - (60 * 60 * 24 * 7)).to_s } # flimsy

  describe "#write" do
    it "writes to the download record" do
      expect(File).to receive(:open).with(*file_args).and_yield(file)
      expect(file).to receive(:write).with(record_data)
      download_record.write(channel: channel, id: id, time: time)
    end
  end

  describe "#read" do
    context "when there is a recorded download" do
      it "returns the time from the record" do
        expect(File).to receive(:exist?).and_return(true)
        expect(File).to receive(:read).with(path).and_return(record_data)
        expect(download_record.read(channel)).to eql(time)
      end
    end

    context "when there is no recorded download" do
      it "returns an older time" do
        expect(File).to receive(:exist?).and_return(false)
        expect(download_record.read(channel).to_s).to eql(old_time)
      end
    end
  end
end

describe VideoDownloader do
  let(:system_caller)   { instance_double("SystemCaller") }
  let(:download_record) { instance_double("DownloadRecord") }
  let(:id)              { "testid" }
  let(:command)         { "youtube-dl \"https://youtu.be/#{id}\"" }
  let(:downloader) do
    described_class.new(
      system_caller: system_caller,
      download_record: download_record)
  end

  let(:record_args) do
    {time:    :some_time,
     channel: :some_channel,
     id:      id}
  end

  describe "#run" do
    context "the system caller returns false" do
      it "does not write to the video record" do
        expect(system_caller).to receive(:run).with(command).
          and_return(false)
        downloader.run(record_args)
      end
    end

    context "the system caller returns true" do
      it "writes to the video record" do
        expect(system_caller).to receive(:run).with(command).
          and_return(true)
        expect(download_record).to receive(:write).with(record_args)
        downloader.run(record_args)
      end
    end
  end
end

describe SystemCaller do
  describe "#run" do
    let(:id)            { "some id" }
    let(:command)       { "this is a command" }
    let(:args)          { [] }
    let(:system_result) { "the result from the system call" }
    let(:system_caller) { described_class.new(args: args) }

    context "the command exits without an error" do
      it "downloads the video" do
        expect(system_caller).to receive(:system).with(command).
          and_return(system_result)
        expect(system_caller.run(command)).to eql(system_result)
      end
    end
  end
end

describe EntryParser do
  let(:page)         { File.read("spec/fixtures/files/videos.xml") }
  let(:entry_parser) { described_class.new }

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
      entries = entry_parser.run(page)
      expect(entries[0]).to eql(channel_entry)
      expect(entries[1]).to eql(video_entry)
    end
  end
end

describe PageDownloader do
  let(:http)            { instance_double("Net::HTTP") }
  let(:page_downloader) { described_class.new(http: http) }
  let(:url)             { "some url" }

  describe "#run" do
    it "downloads the page" do
      expect(http).to receive(:get).with(url)
      page_downloader.run(url)
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
      expect(feed_downloader.run(id: id, type: type)).to eql(feed)
    end
  end
end
