require "spec_helper"

RSpec.describe Lowmu::HugoScanner do
  let(:hugo_dir) { Dir.mktmpdir("hugo_content") }

  after { FileUtils.rm_rf(hugo_dir) }

  def write_md(rel_path, front_matter = {})
    full = File.join(hugo_dir, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    fm = front_matter.map { |k, v| "#{k}: #{v}" }.join("\n")
    File.write(full, "---\n#{fm}\n---\nContent.")
    full
  end

  describe "#scan" do
    it "derives slug from parent directory name for index.md files" do
      write_md("posts/my-post/index.md", title: "My Post")
      result = described_class.new(hugo_dir).scan
      expect(result.map { |r| r[:slug] }).to include("my-post")
    end

    it "derives slug from filename for non-index files" do
      write_md("notes/quick-tip.md", title: "Quick Tip")
      result = described_class.new(hugo_dir).scan
      expect(result.map { |r| r[:slug] }).to include("quick-tip")
    end

    it "uses front matter slug when present" do
      write_md("posts/long-dirname/index.md", title: "Post", slug: "custom")
      result = described_class.new(hugo_dir).scan
      expect(result.map { |r| r[:slug] }).to include("custom")
      expect(result.map { |r| r[:slug] }).not_to include("long-dirname")
    end

    it "includes the full source_path for each entry" do
      write_md("posts/my-post/index.md")
      result = described_class.new(hugo_dir).scan
      expect(result.first[:source_path]).to eq(File.join(hugo_dir, "posts/my-post/index.md"))
    end

    it "returns all discovered markdown files" do
      write_md("posts/post-a/index.md")
      write_md("posts/post-b/index.md")
      write_md("notes/note-a.md")
      result = described_class.new(hugo_dir).scan
      expect(result.length).to eq(3)
    end

    it "returns empty array when hugo_content_dir has no markdown files" do
      expect(described_class.new(hugo_dir).scan).to eq([])
    end
  end
end
