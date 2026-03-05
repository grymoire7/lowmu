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

  def scanner
    described_class.new(hugo_dir, post_dirs: ["posts"], note_dirs: ["notes"])
  end

  describe "#scan" do
    it "derives slug from parent directory name for index.md files" do
      write_md("posts/my-post/index.md", title: "My Post")
      expect(scanner.scan.map { |r| r[:slug] }).to include("my-post")
    end

    it "derives slug from filename for non-index files" do
      write_md("notes/quick-tip.md", title: "Quick Tip")
      expect(scanner.scan.map { |r| r[:slug] }).to include("quick-tip")
    end

    it "uses front matter slug when present" do
      write_md("posts/long-dirname/index.md", title: "Post", slug: "custom")
      slugs = scanner.scan.map { |r| r[:slug] }
      expect(slugs).to include("custom")
      expect(slugs).not_to include("long-dirname")
    end

    it "includes the full source_path for each entry" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:source_path]).to eq(File.join(hugo_dir, "posts/my-post/index.md"))
    end

    it "tags items from post_dirs with content_type :post" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:content_type]).to eq(:post)
    end

    it "tags items from note_dirs with content_type :note" do
      write_md("notes/quick-tip.md")
      result = scanner.scan.first
      expect(result[:content_type]).to eq(:note)
    end

    it "sets section to the directory name" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:section]).to eq("posts")
    end

    it "sets key to section/slug" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:key]).to eq("posts/my-post")
    end

    it "excludes directories not in post_dirs or note_dirs" do
      write_md("posts/post-a/index.md")
      write_md("portfolio/jojo/index.md")
      write_md("about/me.md")
      results = scanner.scan
      expect(results.length).to eq(1)
      expect(results.first[:slug]).to eq("post-a")
    end

    it "scans both post_dirs and note_dirs" do
      write_md("posts/post-a/index.md")
      write_md("posts/post-b/index.md")
      write_md("notes/note-a.md")
      expect(scanner.scan.length).to eq(3)
    end

    it "returns empty array when hugo_content_dir has no matching markdown files" do
      expect(scanner.scan).to eq([])
    end

    it "excludes files with draft: true in front matter" do
      write_md("posts/published/index.md", title: "Published")
      write_md("posts/draft-post/index.md", title: "Draft", draft: true)
      results = scanner.scan
      expect(results.map { |r| r[:slug] }).to include("published")
      expect(results.map { |r| r[:slug] }).not_to include("draft-post")
    end

    it "includes files with draft: false in front matter" do
      write_md("posts/not-a-draft/index.md", title: "Not a Draft", draft: false)
      expect(scanner.scan.map { |r| r[:slug] }).to include("not-a-draft")
    end
  end
end
