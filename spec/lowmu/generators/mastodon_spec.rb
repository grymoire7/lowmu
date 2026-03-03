require "spec_helper"

RSpec.describe Lowmu::Generators::Mastodon do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon_test") }
  let(:target_config) { {"name" => "mastodon", "type" => "mastodon"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def copy_fixture(name)
    FileUtils.cp("spec/fixtures/#{name}",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    context "with type: post" do
      before do
        copy_fixture("sample_post.md")
        mock_llm_response(content: "Interesting post about Ruby! #ruby #testing [URL]")
      end

      it "returns the output filename" do
        result = described_class.new(slug_dir, target_config, llm_config).generate
        expect(result).to eq("mastodon.txt")
      end

      it "creates mastodon.txt in the slug directory" do
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(File.exist?(File.join(slug_dir, "mastodon.txt"))).to be true
      end

      it "calls the LLM with a prompt mentioning the character limit" do
        mock_chat = mock_llm_response(content: "short post #ruby [URL]")
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(mock_chat).to have_received(:ask).with(including("500"))
      end

      it "calls the LLM with the full post content" do
        mock_chat = mock_llm_response(content: "post output #ruby [URL]")
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
      end
    end

    context "with type: note and content within 500 chars" do
      before { copy_fixture("sample_note.md") }

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body (without front matter) to mastodon.txt" do
        described_class.new(slug_dir, target_config, llm_config).generate
        content = File.read(File.join(slug_dir, "mastodon.txt"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end

    context "with type: note and content over 500 chars" do
      before do
        long_body = "A" * 501
        content = "---\ntitle: Long Note\ndate: 2026-03-03\ntype: note\n---\n#{long_body}"
        File.write(File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE), content)
        mock_llm_response(content: "Condensed note #ruby [URL]")
      end

      it "calls the LLM to condense the note" do
        mock_chat = mock_llm_response(content: "Condensed note #ruby [URL]")
        described_class.new(slug_dir, target_config, llm_config).generate
        expect(mock_chat).to have_received(:ask)
      end
    end

    context "when LLM output exceeds 500 chars" do
      before do
        copy_fixture("sample_post.md")
        mock_llm_response(content: "x" * 501)
      end

      it "appends a length warning comment to the file" do
        described_class.new(slug_dir, target_config, llm_config).generate
        content = File.read(File.join(slug_dir, "mastodon.txt"))
        expect(content).to include("<!-- lowmu:")
        expect(content).to include("500")
      end
    end
  end
end
