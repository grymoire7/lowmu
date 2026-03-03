require "spec_helper"

RSpec.describe Lowmu::ContentStore do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:store) { described_class.new(base_dir) }

  after { FileUtils.rm_rf(base_dir) }

  describe "#slug_exists?" do
    it "returns false when slug directory does not exist" do
      expect(store.slug_exists?("my-post")).to be false
    end

    it "returns true after ensure_slug_dir is called" do
      store.ensure_slug_dir("my-post")
      expect(store.slug_exists?("my-post")).to be true
    end
  end

  describe "#ensure_slug_dir" do
    it "creates the slug directory under generated/" do
      store.ensure_slug_dir("my-post")
      expect(Dir.exist?(File.join(base_dir, "generated", "my-post"))).to be true
    end

    it "is idempotent" do
      store.ensure_slug_dir("my-post")
      expect { store.ensure_slug_dir("my-post") }.not_to raise_error
    end
  end

  describe "#write_status and #read_status" do
    it "round-trips status data" do
      status = {"generated_at" => "2026-03-03T12:00:00Z"}
      store.write_status("my-post", status)
      expect(store.read_status("my-post")).to eq(status)
    end

    it "auto-creates the slug directory" do
      store.write_status("my-post", {"generated_at" => "2026-03-03T12:00:00Z"})
      expect(store.slug_exists?("my-post")).to be true
    end

    it "returns empty hash when status file does not exist" do
      store.ensure_slug_dir("my-post")
      expect(store.read_status("my-post")).to eq({})
    end
  end

  describe "#generated_at" do
    it "returns nil when no status.yml exists" do
      store.ensure_slug_dir("my-post")
      expect(store.generated_at("my-post")).to be_nil
    end

    it "returns a Time object from the stored iso8601 string" do
      t = Time.now.utc
      store.write_status("my-post", {"generated_at" => t.iso8601})
      expect(store.generated_at("my-post")).to be_within(1).of(t)
    end
  end

  describe "#slugs" do
    it "returns all slug directory names sorted" do
      store.ensure_slug_dir("post-b")
      store.ensure_slug_dir("post-a")
      expect(store.slugs).to eq(["post-a", "post-b"])
    end

    it "returns empty array when base_dir does not exist" do
      expect(described_class.new("/nonexistent/path").slugs).to eq([])
    end
  end
end
