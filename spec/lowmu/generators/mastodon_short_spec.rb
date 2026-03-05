require "spec_helper"

RSpec.describe Lowmu::Generators::MastodonShort do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon_short_test") }
  let(:target_config) { {"name" => "mastodon", "type" => "mastodon_short"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type = :long)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with type: long" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Interesting post about Ruby! #ruby #testing [URL]") }

      it "returns the output filename" do
        expect(generator(source_path).generate).to eq("mastodon_short.md")
      end

      it "creates mastodon_short.md in the slug directory" do
        generator(source_path).generate
        expect(File.exist?(File.join(slug_dir, "mastodon_short.md"))).to be true
      end

      it "calls the LLM with a prompt mentioning the character limit" do
        mock_chat = mock_llm_response(content: "short post #ruby [URL]")
        generator(source_path).generate
        expect(mock_chat).to have_received(:ask).with(including("500"))
      end

      it "calls the LLM with the full post content" do
        mock_chat = mock_llm_response(content: "post output #ruby [URL]")
        generator(source_path).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
      end
    end

    context "with type: short and content within 500 chars" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        generator(source_path, :short).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body (without front matter) to mastodon_short.md" do
        generator(source_path, :short).generate
        content = File.read(File.join(slug_dir, "mastodon_short.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end

    context "with type: short and content over 500 chars" do
      let(:source_path) do
        path = File.join(slug_dir, "long_note.md")
        File.write(path, "---\ntitle: Long Note\ndate: 2026-03-03\ntype: note\n---\n#{"A" * 501}")
        path
      end

      before { mock_llm_response(content: "Condensed note #ruby [URL]") }

      it "calls the LLM to condense the note" do
        mock_chat = mock_llm_response(content: "Condensed note #ruby [URL]")
        generator(source_path, :short).generate
        expect(mock_chat).to have_received(:ask)
      end
    end

    context "when LLM output exceeds 500 chars" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "x" * 501) }

      it "appends a length warning comment to the file" do
        generator(source_path).generate
        content = File.read(File.join(slug_dir, "mastodon_short.md"))
        expect(content).to include("<!-- lowmu:")
        expect(content).to include("500")
      end
    end
  end
end
