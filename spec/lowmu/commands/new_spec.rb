require "spec_helper"

RSpec.describe Lowmu::Commands::New do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:config) do
    instance_double(Lowmu::Config,
      content_dir: base_dir,
      targets: [])
  end
  let(:image_path) do
    path = File.join(base_dir, "hero.jpg")
    File.write(path, "fake image")
    path
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    subject(:result) do
      described_class.new("spec/fixtures/sample_post.md", image_path, config: config).call
    end

    it "returns the derived slug" do
      expect(result[:slug]).to eq("sample_post")
    end

    it "returns the publish_to targets from front matter" do
      expect(result[:targets]).to include("substack", "mastodon")
    end

    it "creates the slug directory in content_dir" do
      result
      expect(Dir.exist?(File.join(base_dir, "sample_post"))).to be true
    end

    it "writes initial status.yml with all targets set to pending" do
      result
      store = Lowmu::ContentStore.new(base_dir)
      status = store.read_status("sample_post")
      expect(status["substack"]["status"]).to eq("pending")
      expect(status["mastodon"]["status"]).to eq("pending")
    end

    it "raises if the markdown file does not exist" do
      expect {
        described_class.new("/nonexistent.md", image_path, config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end

    it "raises if the image file does not exist" do
      expect {
        described_class.new("spec/fixtures/sample_post.md", "/nonexistent.jpg", config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end
  end
end
