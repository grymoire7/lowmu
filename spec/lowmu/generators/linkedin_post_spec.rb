require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinPost do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_post_test") }
  let(:target_config) { {"name" => "linkedin-post", "type" => "linkedin_post"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with content_type :post" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Professional hook.\n\nKey insight.\n\nRead more: [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :post).generate).to eq("linkedin_post.md")
      end

      it "creates linkedin_post.md" do
        generator(source_path, :post).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_post.md"))).to be true
      end

      it "sends a prompt mentioning LinkedIn" do
        mock_chat = mock_llm_response(content: "LinkedIn post")
        generator(source_path, :post).generate
        expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
      end
    end

    context "with content_type :note" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      before { mock_llm_response(content: "Quick insight on LinkedIn.") }

      it "returns the output filename" do
        expect(generator(source_path, :note).generate).to eq("linkedin_post.md")
      end

      it "creates linkedin_post.md" do
        generator(source_path, :note).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_post.md"))).to be true
      end
    end
  end
end
