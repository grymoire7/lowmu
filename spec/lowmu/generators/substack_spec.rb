require "spec_helper"

RSpec.describe Lowmu::Generators::Substack do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_test") }
  let(:target_config) { {"name" => "substack", "type" => "substack"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type = :post)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  describe "#generate" do
    context "with type: post" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Generated content.") }

      it "returns the post output filename" do
        expect(generator(source_path).generate).to eq(described_class::POST_FILE)
      end

      it "creates substack_post.md" do
        generator(source_path).generate
        expect(File.exist?(File.join(slug_dir, "substack_post.md"))).to be true
      end

      it "creates substack_note.md" do
        generator(source_path).generate
        expect(File.exist?(File.join(slug_dir, "substack_note.md"))).to be true
      end

      it "calls the LLM twice (once for post, once for note)" do
        mock_chat = mock_llm_response(content: "Generated content.")
        generator(source_path).generate
        expect(mock_chat).to have_received(:ask).twice
      end

      it "sends post content to LLM" do
        mock_chat = mock_llm_response(content: "output")
        generator(source_path).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post")).at_least(:once)
      end
    end

    context "with type: note" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      it "returns the note output filename" do
        expect(generator(source_path, :note).generate).to eq(described_class::NOTE_FILE)
      end

      it "creates substack_note.md" do
        generator(source_path, :note).generate
        expect(File.exist?(File.join(slug_dir, "substack_note.md"))).to be true
      end

      it "does not create substack_post.md" do
        generator(source_path, :note).generate
        expect(File.exist?(File.join(slug_dir, "substack_post.md"))).to be false
      end

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        generator(source_path, :note).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body without front matter" do
        generator(source_path, :note).generate
        content = File.read(File.join(slug_dir, "substack_note.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end
  end
end
