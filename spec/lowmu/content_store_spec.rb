require "spec_helper"

RSpec.describe Lowmu::ContentStore do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:store) { described_class.new(base_dir) }

  after { FileUtils.rm_rf(base_dir) }

  describe ".slug_from_path" do
    it "derives slug from a file path" do
      expect(described_class.slug_from_path("/some/path/my-cool-post.md")).to eq("my-cool-post")
    end
  end

  describe "#slug_exists?" do
    it "returns false when slug directory does not exist" do
      expect(store.slug_exists?("my-post")).to be false
    end

    it "returns true when slug directory exists" do
      FileUtils.mkdir_p(File.join(base_dir, "my-post"))
      expect(store.slug_exists?("my-post")).to be true
    end
  end

  describe "#create_slug" do
    let(:md_path) { "spec/fixtures/sample_post.md" }
    let(:image_path) do
      path = File.join(base_dir, "hero.jpg")
      File.write(path, "fake image data")
      path
    end

    it "creates the slug directory" do
      store.create_slug("my-post", md_path, image_path)
      expect(Dir.exist?(File.join(base_dir, "my-post"))).to be true
    end

    it "copies the markdown file as original_content.md" do
      store.create_slug("my-post", md_path, image_path)
      expect(File.exist?(File.join(base_dir, "my-post", "original_content.md"))).to be true
    end

    it "copies the hero image preserving the extension" do
      store.create_slug("my-post", md_path, image_path)
      expect(File.exist?(File.join(base_dir, "my-post", "hero_image.jpg"))).to be true
    end

    it "raises if the slug already exists" do
      FileUtils.mkdir_p(File.join(base_dir, "my-post"))
      expect { store.create_slug("my-post", md_path, image_path) }
        .to raise_error(Lowmu::Error, /already exists/)
    end
  end

  describe "#write_status and #read_status" do
    before { FileUtils.mkdir_p(File.join(base_dir, "my-post")) }

    it "round-trips status data" do
      status = {"substack" => {"status" => "pending"}}
      store.write_status("my-post", status)
      expect(store.read_status("my-post")).to eq(status)
    end

    it "returns empty hash when status file does not exist" do
      expect(store.read_status("my-post")).to eq({})
    end
  end

  describe "#update_target_status" do
    before do
      FileUtils.mkdir_p(File.join(base_dir, "my-post"))
      store.write_status("my-post", {"substack" => {"status" => "pending"}})
    end

    it "merges new attributes into the existing target status" do
      store.update_target_status("my-post", "substack", {"status" => "generated"})
      expect(store.read_status("my-post").dig("substack", "status")).to eq("generated")
    end

    it "preserves existing attributes not being updated" do
      store.update_target_status("my-post", "substack", {"file" => "substack.md"})
      status = store.read_status("my-post")
      expect(status.dig("substack", "status")).to eq("pending")
      expect(status.dig("substack", "file")).to eq("substack.md")
    end
  end

  describe "#slugs" do
    it "returns all slug directory names sorted" do
      FileUtils.mkdir_p(File.join(base_dir, "post-b"))
      FileUtils.mkdir_p(File.join(base_dir, "post-a"))
      expect(store.slugs).to eq(["post-a", "post-b"])
    end

    it "returns empty array when base_dir does not exist" do
      store = described_class.new("/nonexistent/path")
      expect(store.slugs).to eq([])
    end
  end

  describe "#ensure_slug_dir" do
    it "creates the slug directory" do
      store.ensure_slug_dir("my-post")
      expect(Dir.exist?(File.join(base_dir, "my-post"))).to be true
    end

    it "is idempotent (does not raise if dir exists)" do
      store.ensure_slug_dir("my-post")
      expect { store.ensure_slug_dir("my-post") }.not_to raise_error
    end
  end

  describe "#generated_at" do
    before { FileUtils.mkdir_p(File.join(base_dir, "my-post")) }

    it "returns nil when no status.yml exists" do
      expect(store.generated_at("my-post")).to be_nil
    end

    it "returns a Time object from the stored iso8601 string" do
      t = Time.now.utc
      store.write_status("my-post", {"generated_at" => t.iso8601})
      expect(store.generated_at("my-post")).to be_within(1).of(t)
    end
  end
end
