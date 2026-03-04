require "spec_helper"

RSpec.describe Lowmu::ContentStore do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:store) { described_class.new(base_dir) }

  after { FileUtils.rm_rf(base_dir) }

  describe "#slug_exists?" do
    it "returns false when key directory does not exist" do
      expect(store.slug_exists?("posts/my-post")).to be false
    end

    it "returns true after ensure_slug_dir is called" do
      store.ensure_slug_dir("posts/my-post")
      expect(store.slug_exists?("posts/my-post")).to be true
    end
  end

  describe "#ensure_slug_dir" do
    it "creates the key directory under generated/" do
      store.ensure_slug_dir("posts/my-post")
      expect(Dir.exist?(File.join(base_dir, "generated", "posts", "my-post"))).to be true
    end

    it "is idempotent" do
      store.ensure_slug_dir("posts/my-post")
      expect { store.ensure_slug_dir("posts/my-post") }.not_to raise_error
    end
  end

  describe "#ignore_slugs" do
    it "returns empty array when ignore.yml does not exist" do
      expect(store.ignore_slugs).to eq([])
    end

    it "returns compound keys listed in ignore.yml" do
      File.write(File.join(base_dir, "ignore.yml"), ["posts/post-a", "notes/note-b"].to_yaml)
      expect(store.ignore_slugs).to contain_exactly("posts/post-a", "notes/note-b")
    end
  end

  describe "#slugs" do
    it "returns all compound keys sorted" do
      store.ensure_slug_dir("posts/post-b")
      store.ensure_slug_dir("posts/post-a")
      store.ensure_slug_dir("notes/note-a")
      expect(store.slugs).to eq(["notes/note-a", "posts/post-a", "posts/post-b"])
    end

    it "returns empty array when base_dir does not exist" do
      expect(described_class.new("/nonexistent/path").slugs).to eq([])
    end
  end
end
