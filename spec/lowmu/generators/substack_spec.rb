require "spec_helper"

RSpec.describe Lowmu::Generators::Substack do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_test") }
  let(:target_config) { {"name" => "substack", "type" => "substack"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    before { mock_llm_response(content: "# My Test Post\n\nFormatted for Substack.") }

    it "returns the output filename" do
      result = described_class.new(slug_dir, target_config, llm_config).generate
      expect(result).to eq("substack.md")
    end

    it "creates substack.md in the slug directory" do
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(File.exist?(File.join(slug_dir, "substack.md"))).to be true
    end

    it "writes the LLM response to substack.md" do
      described_class.new(slug_dir, target_config, llm_config).generate
      content = File.read(File.join(slug_dir, "substack.md"))
      expect(content).to include("Formatted for Substack")
    end

    it "sends the original content to the LLM" do
      mock_chat = mock_llm_response(content: "output")
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
    end
  end
end
