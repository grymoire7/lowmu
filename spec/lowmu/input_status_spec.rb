require "spec_helper"

RSpec.describe Lowmu::InputStatus do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo") }
  let(:content_dir) { Dir.mktmpdir("lowmu") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }
  let(:source_path) do
    path = File.join(hugo_content_dir, "post.md")
    File.write(path, "---\ntitle: Test\n---\nBody.")
    path
  end

  let(:long_item) { {key: "long/my-post", source_path: source_path, content_type: :long} }
  let(:short_item) { {key: "short/my-note", source_path: source_path, content_type: :short} }

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  def write_output(key, filename, mtime: nil)
    store.ensure_slug_dir(key)
    path = File.join(store.slug_dir(key), filename)
    File.write(path, "generated")
    File.utime(mtime, mtime, path) if mtime
    path
  end

  describe "#call" do
    context "with a long item and two enabled targets" do
      subject(:status) { described_class.new(long_item, ["mastodon_short", "substack_long"], store) }

      it "returns :pending for both when no output exists" do
        result = status.call
        expect(result).to eq("mastodon_short" => :pending, "substack_long" => :pending)
      end

      it "returns :done when output is newer than source" do
        past = Time.now - 120
        File.utime(past, past, source_path)
        write_output("long/my-post", "mastodon_short.md")
        write_output("long/my-post", "substack_long.md")
        result = status.call
        expect(result).to eq("mastodon_short" => :done, "substack_long" => :done)
      end

      it "returns :stale when source is newer than output" do
        past = Time.now - 120
        write_output("long/my-post", "mastodon_short.md", mtime: past)
        result = status.call
        expect(result["mastodon_short"]).to eq(:stale)
      end
    end

    context "with a short item and a long target enabled" do
      subject(:status) { described_class.new(short_item, ["substack_long", "mastodon_short"], store) }

      it "returns :not_applicable for the long target" do
        result = status.call
        expect(result["substack_long"]).to eq(:not_applicable)
      end

      it "returns :pending for the short target" do
        result = status.call
        expect(result["mastodon_short"]).to eq(:pending)
      end
    end
  end

  describe "#aggregate" do
    subject(:status) { described_class.new(long_item, ["mastodon_short", "substack_long"], store) }

    it "returns :pending when no output exists" do
      expect(status.aggregate).to eq(:pending)
    end

    it "returns :done when all applicable outputs are done" do
      past = Time.now - 120
      File.utime(past, past, source_path)
      write_output("long/my-post", "mastodon_short.md")
      write_output("long/my-post", "substack_long.md")
      expect(status.aggregate).to eq(:done)
    end

    it "returns :partial when some but not all outputs are done" do
      past = Time.now - 120
      File.utime(past, past, source_path)
      write_output("long/my-post", "mastodon_short.md")
      expect(status.aggregate).to eq(:partial)
    end

    it "returns :stale when any output is stale" do
      past = Time.now - 120
      write_output("long/my-post", "mastodon_short.md", mtime: past)
      expect(status.aggregate).to eq(:stale)
    end
  end
end
