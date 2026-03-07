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

  describe "#call" do
    context "without a key filter" do
      it "returns an entry for every discovered item" do
        results = described_class.new(nil, config: config).call
        expect(results.map { |r| r[:key] }).to contain_exactly("long/post-a", "short/post-b")
      end

      it "reports :pending for new items" do
        results = described_class.new(nil, config: config).call
        expect(results.map { |r| r[:status] }).to all(eq(:pending))
      end
    end

    context "with a specific key filter" do
      it "returns only that item's entry" do
        results = described_class.new("long/post-a", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:key]).to eq("long/post-a")
      end
    end

    context "with a done item" do
      before do
        store.ensure_slug_dir("long/post-a")
        ["mastodon_short.md", "substack_long.md"].each do |filename|
          File.write(File.join(store.slug_dir("long/post-a"), filename), "generated content")
        end
        past = Time.now - 60
        File.utime(past, past, source_a)
      end

      it "returns :done status" do
        results = described_class.new("long/post-a", config: config).call
        expect(results.first[:status]).to eq(:done)
      end
    end

    context "with a stale item" do
      before do
        store.ensure_slug_dir("long/post-a")
        output = File.join(store.slug_dir("long/post-a"), "mastodon_short.md")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, output)
      end

      it "returns :stale status" do
        results = described_class.new("long/post-a", config: config).call
        expect(results.first[:status]).to eq(:stale)
      end
    end
  end
end
