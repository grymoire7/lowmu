require "spec_helper"

RSpec.describe Lowmu::Generators::Substack do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_test") }
  let(:target_config) { {"name" => "substack", "type" => "substack"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def write_fixture(name)
    FileUtils.cp("spec/fixtures/#{name}",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    context "with type: post" do
      before do
        write_fixture("sample_post.md")
        mock_llm_response(content: "Generated content.")
      end

      it "returns the post output filename" do
        result = described_class.new(slug_dir, target_config, llm_config).generate
        expect(result).to eq(described_class::POST_FILE)
      end

      it "creates substack_post.md" do
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(File.exist?(File.join(slug_dir, "substack_post.md"))).to be true
      end

      it "creates substack_note.md" do
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(File.exist?(File.join(slug_dir, "substack_note.md"))).to be true
      end

      it "calls the LLM twice (once for post, once for note)" do
        mock_chat = mock_llm_response(content: "Generated content.")
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(mock_chat).to have_received(:ask).twice
      end

      it "sends post content to LLM" do
        mock_chat = mock_llm_response(content: "output")
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post")).at_least(:once)
      end
    end

    context "with type: note" do
      before { write_fixture("sample_note.md") }

      it "returns the note output filename" do
        result = described_class.new(slug_dir, target_config, llm_config).generate
        expect(result).to eq(described_class::NOTE_FILE)
      end

      it "creates substack_note.md" do
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(File.exist?(File.join(slug_dir, "substack_note.md"))).to be true
      end

      it "does not create substack_post.md" do
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(File.exist?(File.join(slug_dir, "substack_post.md"))).to be false
      end

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body without front matter" do
        described_class.new(slug_dir, target_config, llm_config).generate
        content = File.read(File.join(slug_dir, "substack_note.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end
  end
end
