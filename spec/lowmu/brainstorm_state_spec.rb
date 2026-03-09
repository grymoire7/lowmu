require "spec_helper"

RSpec.describe Lowmu::BrainstormState do
  let(:content_dir) { Dir.mktmpdir("lowmu_state_test") }
  let(:state) { described_class.new(content_dir) }

  after { FileUtils.rm_rf(content_dir) }

  describe "#cached?" do
    it "returns false for an unknown id" do
      expect(state.cached?("my-source", "abc123")).to be false
    end

    it "returns true after mark_cached" do
      state.mark_cached("my-source", "abc123", "rss/cache/2026-03-08-my-source-foo.md")
      expect(state.cached?("my-source", "abc123")).to be true
    end

    it "returns false for an id from a different source" do
      state.mark_cached("source-a", "abc123", "rss/cache/2026-03-08-source-a-foo.md")
      expect(state.cached?("source-b", "abc123")).to be false
    end
  end

  describe "#cache_path_for" do
    it "returns nil for an unknown id" do
      expect(state.cache_path_for("my-source", "abc123")).to be_nil
    end

    it "returns the path after mark_cached" do
      state.mark_cached("my-source", "abc123", "rss/cache/2026-03-08-my-source-foo.md")
      expect(state.cache_path_for("my-source", "abc123")).to eq("rss/cache/2026-03-08-my-source-foo.md")
    end
  end

  describe "#mark_cached" do
    it "persists to disk" do
      state.mark_cached("my-source", "abc123", "rss/cache/2026-03-08-my-source-foo.md")
      reloaded = described_class.new(content_dir)
      expect(reloaded.cached?("my-source", "abc123")).to be true
    end

    it "accumulates entries across calls" do
      state.mark_cached("my-source", "id1", "rss/cache/path1.md")
      state.mark_cached("my-source", "id2", "rss/cache/path2.md")
      expect(state.cached?("my-source", "id1")).to be true
      expect(state.cached?("my-source", "id2")).to be true
    end

    it "does not duplicate entries" do
      state.mark_cached("my-source", "id1", "rss/cache/path1.md")
      state.mark_cached("my-source", "id1", "rss/cache/path1.md")
      raw = YAML.safe_load_file(File.join(content_dir, "brainstorm_state.yml"))
      expect(raw["sources"]["my-source"]["cached_items"].count { |id, _| id == "id1" }).to eq(1)
    end
  end
end
