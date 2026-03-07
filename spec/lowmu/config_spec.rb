require "spec_helper"

RSpec.describe Lowmu::Config do
  let(:fixture_path) { "spec/fixtures/sample_config.yml" }

  describe ".load" do
    it "loads a valid config file" do
      config = described_class.load(fixture_path)
      expect(config).to be_a(described_class)
    end

    it "raises an error when the file does not exist" do
      expect { described_class.load("/nonexistent/config.yml") }
        .to raise_error(Lowmu::Error, /not found/)
    end
  end

  describe "#hugo_content_dir" do
    it "returns the expanded hugo content directory path" do
      config = described_class.load(fixture_path)
      expect(config.hugo_content_dir).to eq("/tmp/lowmu_test_hugo_content")
    end
  end

  describe "#content_dir" do
    it "returns the expanded content directory path" do
      config = described_class.load(fixture_path)
      expect(config.content_dir).to eq("/tmp/lowmu_test_content")
    end

    it "defaults to .lowmu when not specified" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"]})
      expect(config.content_dir).to eq(File.expand_path(".lowmu"))
    end
  end

  describe "#llm" do
    it "returns the llm configuration hash" do
      config = described_class.load(fixture_path)
      expect(config.llm["model"]).to eq("claude-opus-4-6")
    end
  end

  describe "#targets" do
    it "returns an array of type name strings" do
      config = described_class.load(fixture_path)
      expect(config.targets).to contain_exactly(
        "linkedin_long", "linkedin_short", "mastodon_short",
        "substack_long", "substack_short"
      )
    end
  end

  describe "#post_dirs" do
    it "defaults to ['posts']" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"]})
      expect(config.post_dirs).to eq(["posts"])
    end

    it "returns configured value" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"], "post_dirs" => ["posts", "articles"]})
      expect(config.post_dirs).to eq(["posts", "articles"])
    end
  end

  describe "#note_dirs" do
    it "defaults to ['notes']" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"]})
      expect(config.note_dirs).to eq(["notes"])
    end

    it "returns configured value" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"], "note_dirs" => ["notes", "microblog"]})
      expect(config.note_dirs).to eq(["notes", "microblog"])
    end
  end

  describe "validation" do
    it "raises when hugo_content_dir is missing" do
      expect { described_class.new({}) }
        .to raise_error(Lowmu::Error, /hugo_content_dir/)
    end

    it "does not raise when content_dir is missing (uses default)" do
      expect { described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"]}) }.not_to raise_error
    end

    it "raises when a target type is not in the registry" do
      data = {"hugo_content_dir" => "/tmp", "targets" => ["unknown_type"]}
      expect { described_class.new(data) }
        .to raise_error(Lowmu::Error, /Unknown target type: unknown_type/)
    end

    it "raises when targets list is empty" do
      data = {"hugo_content_dir" => "/tmp", "targets" => []}
      expect { described_class.new(data) }
        .to raise_error(Lowmu::Error, /targets/)
    end
  end
end
