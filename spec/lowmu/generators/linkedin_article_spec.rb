require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinArticle do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_article_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "linkedin-article", "type" => "linkedin_article"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :post, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    before { mock_llm_response(content: "# Article Headline\n\nExpanded article content.") }

    it "returns the output filename" do
      expect(generator.generate).to eq("linkedin_article.md")
    end

    it "creates linkedin_article.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "linkedin_article.md"))).to be true
    end

    it "sends post content to LLM" do
      mock_chat = mock_llm_response(content: "article output")
      generator.generate
      expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
    end
  end
end
