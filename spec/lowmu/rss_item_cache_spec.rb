require "spec_helper"

RSpec.describe Lowmu::RssItemCache do
  let(:content_dir) { Dir.mktmpdir("lowmu_cache_test") }
  let(:cache) { described_class.new(content_dir) }
  let(:item) do
    {
      id: "https://example.com/post-1",
      title: "First Post About Ruby",
      url: "https://example.com/post-1",
      source_name: "example-blog",
      body: "Ruby is a great language. " * 50
    }
  end

  after { FileUtils.rm_rf(content_dir) }

  describe "#write" do
    it "returns a relative path starting with rss/cache/" do
      path = cache.write(item)
      expect(path).to start_with("rss/cache/")
    end

    it "returns a path ending in .md" do
      expect(cache.write(item)).to end_with(".md")
    end

    it "includes today's date in the filename" do
      expect(cache.write(item)).to include(Date.today.to_s)
    end

    it "creates the file on disk" do
      path = cache.write(item)
      expect(File.exist?(File.join(content_dir, path))).to be true
    end

    it "writes YAML front matter with title, url, source_name, fetched_at, full_content" do
      path = cache.write(item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("title: \"First Post About Ruby\"")
      expect(content).to include("url: https://example.com/post-1")
      expect(content).to include("source_name: example-blog")
      expect(content).to include("fetched_at: #{Date.today}")
    end

    it "marks full_content true when body exceeds 200 words" do
      path = cache.write(item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("full_content: true")
    end

    it "marks full_content false for a short body" do
      short_item = item.merge(body: "Just a short summary.")
      path = cache.write(short_item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("full_content: false")
    end

    it "writes the body after front matter" do
      path = cache.write(item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("Ruby is a great language.")
    end

    it "creates parent directories if they do not exist" do
      new_dir = File.join(Dir.mktmpdir, "new_content")
      described_class.new(new_dir).write(item)
      expect(Dir.exist?(File.join(new_dir, "rss", "cache"))).to be true
    end
  end
end
