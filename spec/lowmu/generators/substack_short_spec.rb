require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackShort do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_short_test") }
  let(:target_config) { {"name" => "substack-short", "type" => "substack_short"} }
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

      before { mock_llm_response(content: "Short note announcing post. [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :long).generate).to eq("substack_short.md")
      end

      it "creates substack_short.md" do
        generator(source_path, :long).generate
        expect(File.exist?(File.join(slug_dir, "substack_short.md"))).to be true
      end

      it "calls the LLM to generate a note from the post" do
        mock_chat = mock_llm_response(content: "Note about post. [URL]")
        generator(source_path, :long).generate
        expect(mock_chat).to have_received(:ask).once
      end

      it "sends post content to LLM" do
        mock_chat = mock_llm_response(content: "output")
        generator(source_path, :long).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
      end
    end

    context "with content_type :short" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      it "returns the output filename" do
        expect(generator(source_path, :short).generate).to eq("substack_short.md")
      end

      it "creates substack_short.md" do
        generator(source_path, :short).generate
        expect(File.exist?(File.join(slug_dir, "substack_short.md"))).to be true
      end

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        generator(source_path, :short).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body without front matter" do
        generator(source_path, :short).generate
        content = File.read(File.join(slug_dir, "substack_short.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end
  end
end
