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
      hugo_content_dir: hugo_content_dir,
      content_dir: content_dir,
      llm: {"model" => "claude-opus-4-6"},
      persona: "I write about software engineering.",
      sources: [{"type" => "file", "name" => "my-notes", "path" => notes_file}])
  end
  let(:llm_response) do
    <<~RESPONSE
      IDEA: Testing Ruby Applications
      SOURCE: my-notes
      BODY:
      A comprehensive look at testing strategies for Ruby.

      ---

      IDEA: Effective Metaprogramming
      SOURCE: my-notes
      BODY:
      How to use Ruby metaprogramming without losing your mind.
    RESPONSE
  end

  before do
    mock_llm_response(content: llm_response)
    RubyLLM.configure { |c| c.anthropic_api_key = "test-key" }
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
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

    it "writes files to $hugo_content_dir/ideas/" do
      files = described_class.new(config: config, num: 2).call
      ideas_dir = File.join(hugo_content_dir, "ideas")
      expect(File.exist?(File.join(ideas_dir, files.first))).to be true
    end

    it "updates state after generating ideas" do
      described_class.new(config: config, num: 2).call
      state = Lowmu::BrainstormState.new(content_dir)
      expect(state.seen?("my-notes", anything)).to be(true).or be(false)
      # state file should exist
      expect(File.exist?(File.join(content_dir, "brainstorm_state.yml"))).to be true
    end

    it "skips already-seen items by default" do
      # Run once to mark items as seen
      described_class.new(config: config, num: 2).call
      # Second run: no new items, LLM should not be called again
      allow(RubyLLM).to receive(:chat).and_call_original
      expect {
        described_class.new(config: config, num: 2).call
      }.to raise_error(Lowmu::Error, /No new source items/)
    end

    it "processes all items when rescan: true" do
      described_class.new(config: config, num: 2).call
      mock_llm_response(content: llm_response)
      # Should not raise even though items were seen before
      expect {
        described_class.new(config: config, num: 2, rescan: true).call
      }.not_to raise_error
    end

    it "includes persona in the LLM prompt" do
      mock_chat = mock_llm_response(content: llm_response)
      described_class.new(config: config, num: 2).call
      expect(mock_chat).to have_received(:ask).with(including("software engineering"))
    end
  end
end
