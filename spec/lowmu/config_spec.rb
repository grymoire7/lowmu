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
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo"})
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
    it "returns all configured targets" do
      config = described_class.load(fixture_path)
      expect(config.targets.length).to eq(5)
    end
  end

  describe "#target_config" do
    it "returns the config hash for a known target" do
      config = described_class.load(fixture_path)
      target = config.target_config("mastodon")
      expect(target["type"]).to eq("mastodon_short")
    end

    it "raises an error for an unknown target" do
      config = described_class.load(fixture_path)
      expect { config.target_config("nonexistent") }
        .to raise_error(Lowmu::Error, /Unknown target/)
    end
  end

  describe "#post_dirs" do
    it "defaults to ['posts']" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo"})
      expect(config.post_dirs).to eq(["posts"])
    end

    it "returns configured value" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "post_dirs" => ["posts", "articles"]})
      expect(config.post_dirs).to eq(["posts", "articles"])
    end
  end

  describe "#note_dirs" do
    it "defaults to ['notes']" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo"})
      expect(config.note_dirs).to eq(["notes"])
    end

    it "returns configured value" do
      config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "note_dirs" => ["notes", "microblog"]})
      expect(config.note_dirs).to eq(["notes", "microblog"])
    end
  end

  describe "validation" do
    it "raises when hugo_content_dir is missing" do
      expect { described_class.new({}) }
        .to raise_error(Lowmu::Error, /hugo_content_dir/)
    end

    it "does not raise when content_dir is missing (uses default)" do
      expect { described_class.new({"hugo_content_dir" => "/tmp/hugo"}) }.not_to raise_error
    end

    it "raises when a target is missing the name key" do
      data = {"hugo_content_dir" => "/tmp", "targets" => [{"type" => "hugo"}]}
      expect { described_class.new(data) }.to raise_error(Lowmu::Error, /name/)
    end

    it "raises when a target is missing the type key" do
      data = {"hugo_content_dir" => "/tmp", "targets" => [{"name" => "myblog"}]}
      expect { described_class.new(data) }.to raise_error(Lowmu::Error, /type/)
    end
  end
end
