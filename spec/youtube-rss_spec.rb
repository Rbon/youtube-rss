require "youtube-rss"

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
