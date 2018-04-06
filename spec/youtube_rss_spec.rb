require "youtube_rss"

describe Main do
  describe "#run" do
    before do
      @channel_dbl = double("Channel")
      @video_dbl = double("Video")
      @feed = File.read("spec/fixtures/files/videos.xml")
    end

    # this should be much better
    it "runs the script" do
      expect(File).to receive(:readlines).and_return(["test"])
      main = Main.new

      expect(FeedGenerator).to receive(:run)
      expect(HTTPDownloader).to receive(:run).and_return(@feed)
      vid_dlr_dbl = double("VideoDownloader")
      expect(vid_dlr_dbl).to receive(:run).exactly(15).times
      expect(VideoDownloader).to receive(:new).exactly(15).times.
        and_return(vid_dlr_dbl)
      expect(Cache).to receive(:update).exactly(15).times
      expect(Cache).to receive(:sync_time).exactly(15).times.
        and_return(Time.parse("2008-01-01"))
      expect(main).to receive(:puts)
      main.run
    end
  end
end

describe FeedGenerator do
  describe ".download" do
    before do
      @id = "test_id"
      @fake_page = File.read("spec/fixtures/files/videos.xml")
    end

    context "with the old channel name type" do
      it "returns a proper feed url" do
        url = "user/#{@id}"
        expect(FeedGenerator.run(url)).
          to eql("https://www.youtube.com/feeds/videos.xml?user=test_id")
      end
    end

    context "with the new channel id type" do
      it "returns a proper feed url" do
        url = "channel/#{@id}"
        expect(FeedGenerator.run(url)).
          to eql("https://www.youtube.com/feeds/videos.xml?channel_id=test_id")
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

describe VideoDownloader do
  before do
    @downloader = VideoDownloader.new
  end

  describe "#run" do
    context "when youtube-dl doesn't exist" do
      before do
        @pathbak = ENV["PATH"]
        ENV["PATH"] = ""
      end

      it "dies" do
        expect(@downloader).to receive(:die)
        @downloader.run(id: "test")
      end

      after do
        ENV["PATH"] = @pathbak
      end
    end


    context "given a valid youtube id" do
      it "downloads the video" do
        id = "testid"
        expect(@downloader).to receive(:system).
          with("youtube-dl #{id}").
          and_return(true)
        @downloader.run(id: id)
      end
    end
  end

  describe "#die" do
    it "complains and exits" do
      expect(@downloader).to receive(:puts).with("ERROR")
      expect(@downloader).to receive(:exit)
      @downloader.die
    end
  end
end
