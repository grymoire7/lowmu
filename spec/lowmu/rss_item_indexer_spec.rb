require "spec_helper"

RSpec.describe Lowmu::RssItemIndexer do
  let(:content_dir) { Dir.mktmpdir("lowmu_indexer_test") }
  let(:cache_relative_path) { "rss/cache/2026-03-08-example-blog-first-post.md" }
  let(:cache_full_path) { File.join(content_dir, cache_relative_path) }
  let(:index_relative_path) { "rss/index/2026-03-08-example-blog-first-post.json" }
  let(:llm_response) do
    <<~JSON
      {
        "concept": "Ruby metaprogramming for DSLs",
        "angle": "Practical guide",
        "audience": "Intermediate Ruby developers",
        "examples": "method_missing, define_method",
        "conclusion": "Use sparingly"
      }
    JSON
  end
  let(:indexer) { described_class.new(content_dir: content_dir, model: "claude-haiku-4-5-20251001") }

  before do
    FileUtils.mkdir_p(File.dirname(cache_full_path))
    File.write(cache_full_path, <<~MD)
      ---
      title: "First Post About Ruby"
      url: https://example.com/post-1
      source_name: example-blog
      fetched_at: 2026-03-08
      full_content: true
      ---

      Ruby is a great language for DSLs.
    MD
    mock_llm_response(content: llm_response)
    RubyLLM.configure { |c| c.anthropic_api_key = "test-key" }
  end

  after { FileUtils.rm_rf(content_dir) }

  describe "#index" do
    it "returns the relative index file path" do
      result = indexer.index(cache_relative_path)
      expect(result).to eq(index_relative_path)
    end

    it "creates the index file on disk" do
      indexer.index(cache_relative_path)
      expect(File.exist?(File.join(content_dir, index_relative_path))).to be true
    end

    it "writes valid JSON with all required fields" do
      indexer.index(cache_relative_path)
      data = JSON.parse(File.read(File.join(content_dir, index_relative_path)))
      expect(data["title"]).to eq("First Post About Ruby")
      expect(data["url"]).to eq("https://example.com/post-1")
      expect(data["source_name"]).to eq("example-blog")
      expect(data["cache_path"]).to eq(cache_relative_path)
      expect(data["concept"]).to eq("Ruby metaprogramming for DSLs")
      expect(data["angle"]).to eq("Practical guide")
      expect(data["audience"]).to eq("Intermediate Ruby developers")
      expect(data["examples"]).to eq("method_missing, define_method")
      expect(data["conclusion"]).to eq("Use sparingly")
    end

    it "skips LLM call and returns path if index file already exists" do
      indexer.index(cache_relative_path)
      # Reset mock to detect if LLM is called again
      mock_chat = mock_llm_response(content: llm_response)
      result = indexer.index(cache_relative_path)
      expect(mock_chat).not_to have_received(:ask)
      expect(result).to eq(index_relative_path)
    end

    context "with --rescan" do
      let(:indexer) { described_class.new(content_dir: content_dir, model: "claude-haiku-4-5-20251001", rescan: true) }

      it "re-runs the LLM even if index file exists" do
        indexer.index(cache_relative_path)
        mock_chat = mock_llm_response(content: llm_response)
        indexer.index(cache_relative_path)
        expect(mock_chat).to have_received(:ask)
      end
    end
  end
end
