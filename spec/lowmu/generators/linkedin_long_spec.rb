require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinLong do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_long_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "linkedin-long", "type" => "linkedin_long"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :long, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    before { mock_llm_response(content: "## LinkedIn Article\n\nContent here.\n\nFollow for more.") }

    it "returns the output filename" do
      expect(generator.generate).to eq("linkedin_long.md")
    end

    it "creates linkedin_long.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "linkedin_long.md"))).to be true
    end

    it "sends a prompt mentioning LinkedIn" do
      mock_chat = mock_llm_response(content: "LinkedIn article")
      generator.generate
      expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
    end
  end
end
