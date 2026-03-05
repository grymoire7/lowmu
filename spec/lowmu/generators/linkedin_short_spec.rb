require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinShort do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_short_test") }
  let(:target_config) { {"name" => "linkedin-short", "type" => "linkedin_short"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with content_type :long" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Professional hook.\n\nKey insight.\n\nRead more: [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :long).generate).to eq("linkedin_short.md")
      end

      it "creates linkedin_short.md" do
        generator(source_path, :long).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_short.md"))).to be true
      end

      it "sends a prompt mentioning LinkedIn" do
        mock_chat = mock_llm_response(content: "LinkedIn post")
        generator(source_path, :long).generate
        expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
      end
    end

    context "with content_type :short" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      before { mock_llm_response(content: "Quick insight on LinkedIn.") }

      it "returns the output filename" do
        expect(generator(source_path, :short).generate).to eq("linkedin_short.md")
      end

      it "creates linkedin_short.md" do
        generator(source_path, :short).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_short.md"))).to be true
      end
    end
  end
end
