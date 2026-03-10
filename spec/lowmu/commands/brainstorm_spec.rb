require "spec_helper"

RSpec.describe Lowmu::Commands::Brainstorm do
  let(:hugo_content_dir) { Dir.mktmpdir("lowmu_hugo") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:notes_file) do
    path = File.join(Dir.mktmpdir, "ideas.md")
    File.write(path, "## Ruby Testing Tips\nGreat ideas about testing.\n\n## Metaprogramming Patterns\nPatterns for Ruby metaprogramming.\n")
    path
  end
  let(:config) do
    instance_double(Lowmu::Config,
      content_dir: content_dir,
      llm: {"model" => "claude-opus-4-6"},
      index_model: "claude-opus-4-6",
      persona: "I write about software engineering.",
      sources: [{"type" => "file", "name" => "my-notes", "path" => notes_file}])
  end
  let(:llm_response) do
    <<~RESPONSE
      TITLE: Testing Ruby Applications
      CONCEPT_SOURCE: fresh
      ANGLE_SOURCE: fresh
      AUDIENCE_SOURCE: fresh
      EXAMPLES_SOURCE: fresh
      CONCLUSION_SOURCE: fresh
      BODY:
      A comprehensive look at testing strategies for Ruby.

      ---

      TITLE: Effective Metaprogramming
      CONCEPT_SOURCE: fresh
      ANGLE_SOURCE: fresh
      AUDIENCE_SOURCE: fresh
      EXAMPLES_SOURCE: fresh
      CONCLUSION_SOURCE: fresh
      BODY:
      How to use Ruby metaprogramming without losing your mind.
    RESPONSE
  end

  before do
    mock_llm_response(content: llm_response)
    RubyLLM.configure { |c| c.anthropic_api_key = "test-key" }
  end

  after do
    FileUtils.rm_rf([hugo_content_dir, content_dir])
  end

  describe "#call" do
    it "returns an array of generated filenames" do
      files = described_class.new(config: config, num: 2).call
      expect(files.length).to eq(2)
    end

    it "writes long-form idea files by default" do
      files = described_class.new(config: config, num: 2).call
      expect(files.first).to start_with("long-")
    end

    it "writes short-form idea files when form is short" do
      files = described_class.new(config: config, form: "short", num: 2).call
      expect(files.first).to start_with("short-")
    end

    it "writes files to $content_dir/ideas/" do
      files = described_class.new(config: config, num: 2).call
      ideas_dir = File.join(content_dir, "ideas")
      expect(File.exist?(File.join(ideas_dir, files.first))).to be true
    end

    context "when the LLM response uses variant formatting" do
      it "parses ideas when separators have trailing whitespace" do
        variant_response = <<~RESPONSE
          TITLE: Testing Ruby Applications
          CONCEPT_SOURCE: fresh
          ANGLE_SOURCE: fresh
          AUDIENCE_SOURCE: fresh
          EXAMPLES_SOURCE: fresh
          CONCLUSION_SOURCE: fresh
          BODY:
          A comprehensive look at testing strategies for Ruby.

          ---

          TITLE: Effective Metaprogramming
          CONCEPT_SOURCE: fresh
          ANGLE_SOURCE: fresh
          AUDIENCE_SOURCE: fresh
          EXAMPLES_SOURCE: fresh
          CONCLUSION_SOURCE: fresh
          BODY:
          How to use Ruby metaprogramming without losing your mind.
        RESPONSE
        mock_llm_response(content: variant_response)
        files = described_class.new(config: config, num: 2).call
        expect(files.length).to eq(2)
      end

      it "parses ideas when BODY content is on the same line as BODY:" do
        inline_body_response = <<~RESPONSE
          TITLE: Testing Ruby Applications
          CONCEPT_SOURCE: fresh
          ANGLE_SOURCE: fresh
          AUDIENCE_SOURCE: fresh
          EXAMPLES_SOURCE: fresh
          CONCLUSION_SOURCE: fresh
          BODY: A comprehensive look at testing strategies for Ruby.

          ---

          TITLE: Effective Metaprogramming
          CONCEPT_SOURCE: fresh
          ANGLE_SOURCE: fresh
          AUDIENCE_SOURCE: fresh
          EXAMPLES_SOURCE: fresh
          CONCLUSION_SOURCE: fresh
          BODY: How to use Ruby metaprogramming without losing your mind.
        RESPONSE
        mock_llm_response(content: inline_body_response)
        files = described_class.new(config: config, num: 2).call
        expect(files.length).to eq(2)
      end
    end

    it "includes persona in the LLM prompt" do
      mock_chat = mock_llm_response(content: llm_response)
      described_class.new(config: config, num: 2).call
      expect(mock_chat).to have_received(:ask).with(including("software engineering"))
    end

    context "with an RSS source" do
      let(:fixture_xml) { File.read("spec/fixtures/sample_feed.xml") }
      let(:rss_config) do
        instance_double(Lowmu::Config,
          content_dir: content_dir,
          llm: {"model" => "claude-opus-4-6"},
          index_model: "claude-opus-4-6",
          persona: "I write about software engineering.",
          sources: [{"type" => "rss", "name" => "example-blog", "url" => "https://example.com/feed.xml"}])
      end
      let(:index_json) do
        '{"concept":"test concept","angle":"test angle","audience":"test audience","examples":"test examples","conclusion":"test conclusion"}'
      end

      before do
        stub_request(:get, "https://example.com/feed.xml").to_return(body: fixture_xml, headers: {"Content-Type" => "application/rss+xml"})
        index_response = instance_double(RubyLLM::Message, content: index_json)
        index_chat = instance_double(RubyLLM::Chat, ask: index_response)
        brainstorm_response = instance_double(RubyLLM::Message, content: llm_response)
        brainstorm_chat = instance_double(RubyLLM::Chat, ask: brainstorm_response)
        # fixture has 2 items → 2 indexer LLM calls, then 1 brainstorm call
        allow(RubyLLM).to receive(:chat).and_return(index_chat, index_chat, brainstorm_chat)
      end

      it "creates cache files under rss/cache/" do
        described_class.new(config: rss_config, num: 1).call
        cache_dir = File.join(content_dir, "rss", "cache")
        expect(Dir.exist?(cache_dir)).to be true
        expect(Dir.glob("#{cache_dir}/*.md")).not_to be_empty
      end

      it "creates index files under rss/index/" do
        described_class.new(config: rss_config, num: 1).call
        index_dir = File.join(content_dir, "rss", "index")
        expect(Dir.exist?(index_dir)).to be true
        expect(Dir.glob("#{index_dir}/*.json")).not_to be_empty
      end

      it "does not re-cache items on a second run" do
        described_class.new(config: rss_config, num: 1).call
        cache_dir = File.join(content_dir, "rss", "cache")
        files_after_first = Dir.glob("#{cache_dir}/*.md").length
        described_class.new(config: rss_config, num: 1).call
        expect(Dir.glob("#{cache_dir}/*.md").length).to eq(files_after_first)
      end
    end

    it "invokes with_progress for each phase" do
      messages = []
      progress = ->(msg, &block) {
        messages << msg
        block.call
      }
      described_class.new(config: config, num: 2, with_progress: progress).call
      expect(messages).to include(
        a_string_matching(/RSS/i),
        a_string_matching(/index/i),
        a_string_matching(/ideas/i)
      )
    end

    it "raises an error when no source items are available" do
      empty_file = File.join(Dir.mktmpdir, "empty.md")
      FileUtils.touch(empty_file)
      empty_config = instance_double(Lowmu::Config,
        content_dir: content_dir,
        llm: {"model" => "claude-opus-4-6"},
        index_model: "claude-opus-4-6",
        persona: "...",
        sources: [{"type" => "file", "name" => "empty", "path" => empty_file}])
      expect { described_class.new(config: empty_config, num: 2).call }
        .to raise_error(Lowmu::Error, /No source items/)
    end
  end
end
