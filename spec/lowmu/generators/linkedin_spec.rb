require "spec_helper"

RSpec.describe Lowmu::Generators::Linkedin do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "linkedin", "type" => "linkedin"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  describe "#generate" do
    before do
      mock_llm_response(content: "Professional hook line.\n\nKey insight here.\n\nRead more: [URL]")
    end

    it "returns the output filename" do
      result = described_class.new(slug_dir, source_path, target_config, llm_config).generate
      expect(result).to eq("linkedin.md")
    end

    it "creates linkedin.md in the slug directory" do
      described_class.new(slug_dir, source_path, target_config, llm_config).generate
      expect(File.exist?(File.join(slug_dir, "linkedin.md"))).to be true
    end

    it "sends a prompt mentioning LinkedIn" do
      mock_chat = mock_llm_response(content: "LinkedIn post")
      described_class.new(slug_dir, source_path, target_config, llm_config).generate
      expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
    end
  end
end
