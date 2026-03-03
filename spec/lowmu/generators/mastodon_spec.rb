require "spec_helper"

RSpec.describe Lowmu::Generators::Mastodon do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon_test") }
  let(:target_config) { {"name" => "mastodon", "type" => "mastodon"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    before do
      mock_llm_response(content: "Interesting post about Ruby! #ruby #testing [URL]")
    end

    it "returns the output filename" do
      result = described_class.new(slug_dir, target_config, llm_config).generate
      expect(result).to eq("mastodon.txt")
    end

    it "creates mastodon.txt in the slug directory" do
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(File.exist?(File.join(slug_dir, "mastodon.txt"))).to be true
    end

    it "sends a prompt mentioning the character limit" do
      mock_chat = mock_llm_response(content: "short post #ruby [URL]")
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(mock_chat).to have_received(:ask).with(including("500"))
    end
  end
end
