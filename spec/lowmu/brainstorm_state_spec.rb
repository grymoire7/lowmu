require "spec_helper"

RSpec.describe Lowmu::BrainstormState do
  let(:content_dir) { Dir.mktmpdir("lowmu_state_test") }
  let(:state) { described_class.new(content_dir) }

  after { FileUtils.rm_rf(content_dir) }

  describe "#seen?" do
    it "returns false for an unknown id" do
      expect(state.seen?("my-source", "abc123")).to be false
    end

    it "returns true after mark_seen" do
      state.mark_seen("my-source", ["abc123"])
      expect(state.seen?("my-source", "abc123")).to be true
    end

    it "returns false for an id from a different source" do
      state.mark_seen("source-a", ["abc123"])
      expect(state.seen?("source-b", "abc123")).to be false
    end
  end

  describe "#mark_seen" do
    it "persists state to disk" do
      state.mark_seen("my-source", ["abc123"])
      reloaded = described_class.new(content_dir)
      expect(reloaded.seen?("my-source", "abc123")).to be true
    end

    it "accumulates ids across calls" do
      state.mark_seen("my-source", ["id1"])
      state.mark_seen("my-source", ["id2"])
      expect(state.seen?("my-source", "id1")).to be true
      expect(state.seen?("my-source", "id2")).to be true
    end

    it "does not duplicate ids" do
      state.mark_seen("my-source", ["id1"])
      state.mark_seen("my-source", ["id1"])
      state_file = YAML.safe_load_file(File.join(content_dir, "brainstorm_state.yml"))
      expect(state_file["sources"]["my-source"]["last_seen_ids"].count("id1")).to eq(1)
    end
  end
end
