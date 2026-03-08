require "spec_helper"

RSpec.describe Lowmu::Commands::Status do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo_content") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }

  let(:config) do
    instance_double(Lowmu::Config,
      hugo_content_dir: hugo_content_dir,
      content_dir: content_dir,
      post_dirs: ["posts"],
      note_dirs: ["notes"],
      targets: ["mastodon_short", "substack_long"])
  end

  let(:source_a) { File.join(hugo_content_dir, "posts", "post-a", "index.md") }
  let(:source_b) { File.join(hugo_content_dir, "notes", "post-b.md") }

  before do
    FileUtils.mkdir_p(File.join(hugo_content_dir, "posts", "post-a"))
    File.write(source_a, "---\ntitle: Post A\n---\nContent.")
    FileUtils.mkdir_p(File.join(hugo_content_dir, "notes"))
    File.write(source_b, "---\ntitle: Post B\n---\nContent.")
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  def write_output(key, filename, mtime: nil)
    store.ensure_slug_dir(key)
    path = File.join(store.slug_dir(key), filename)
    File.write(path, "generated")
    File.utime(mtime, mtime, path) if mtime
  end

  def call(filters = {})
    described_class.new(nil, config: config, filters: filters).call
  end

  describe "#call" do
    it "returns all targets as column headers" do
      expect(call[:targets]).to eq(["mastodon_short", "substack_long"])
    end

    it "returns a row for every discovered item with no filter" do
      result = call
      expect(result[:rows].map { |r| r[:key] }).to contain_exactly("long/post-a", "short/post-b")
    end

    it "marks substack_long as :not_applicable for short content" do
      result = call
      short_row = result[:rows].find { |r| r[:key] == "short/post-b" }
      expect(short_row[:statuses]["substack_long"]).to eq(:not_applicable)
    end

    context "with --pending filter" do
      it "includes items with at least one pending target" do
        result = call(pending: true)
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes fully done items" do
        past = Time.now - 120
        File.utime(past, past, source_a)
        write_output("long/post-a", "mastodon_short.md")
        write_output("long/post-a", "substack_long.md")
        result = call(pending: true)
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end
    end

    context "with --done filter" do
      it "includes items where all applicable outputs are done" do
        past = Time.now - 120
        File.utime(past, past, source_a)
        write_output("long/post-a", "mastodon_short.md")
        write_output("long/post-a", "substack_long.md")
        result = call(done: true)
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes pending items" do
        result = call(done: true)
        expect(result[:rows]).to be_empty
      end
    end

    context "with --stale filter" do
      it "includes items with at least one stale output" do
        past = Time.now - 120
        write_output("long/post-a", "mastodon_short.md", mtime: past)
        result = call(stale: true)
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end
    end

    context "with --no-stale filter" do
      it "excludes items with any stale output" do
        past = Time.now - 120
        write_output("long/post-a", "mastodon_short.md", mtime: past)
        result = call(no_stale: true)
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end
    end

    context "with --recent filter" do
      it "includes items with output created within the duration" do
        write_output("long/post-a", "mastodon_short.md")
        result = call(recent: "1w")
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes items whose output is older than the duration" do
        old = Time.now - (10 * 86_400)
        write_output("long/post-a", "mastodon_short.md", mtime: old)
        result = call(recent: "3d")
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end

      it "includes items with no output but recently modified source" do
        result = call(recent: "1w")
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes items with no output and old source" do
        old = Time.now - (10 * 86_400)
        File.utime(old, old, source_a)
        result = call(recent: "3d")
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end
    end

    context "with a key filter (specific slug)" do
      it "returns only that item" do
        result = described_class.new("long/post-a", config: config, filters: {}).call
        expect(result[:rows].map { |r| r[:key] }).to contain_exactly("long/post-a")
      end
    end
  end
end
