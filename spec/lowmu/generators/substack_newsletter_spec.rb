require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackNewsletter do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_newsletter_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "substack-newsletter", "type" => "substack_newsletter"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :post, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    before { mock_llm_response(content: "Reformatted newsletter content.") }

    it "returns the output filename" do
      expect(generator.generate).to eq("substack_newsletter.md")
    end

    it "creates substack_newsletter.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "substack_newsletter.md"))).to be true
    end

    it "calls the LLM once" do
      mock_chat = mock_llm_response(content: "Newsletter content.")
      generator.generate
      expect(mock_chat).to have_received(:ask).once
    end

    it "sends post content to LLM" do
      mock_chat = mock_llm_response(content: "output")
      generator.generate
      expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
    end
  end
end
