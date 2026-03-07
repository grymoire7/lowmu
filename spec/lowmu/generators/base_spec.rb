require "spec_helper"

RSpec.describe Lowmu::Generators do
  describe ".registry" do
    it "returns a hash with all expected type keys" do
      expect(described_class.registry.keys).to contain_exactly(
        "substack_long", "substack_short", "mastodon_short",
        "linkedin_short", "linkedin_long"
      )
    end

    it "maps each key to a class with FORM and OUTPUT_FILE" do
      described_class.registry.each_value do |klass|
        expect(klass).to respond_to(:const_get)
        expect([:long, :short]).to include(klass::FORM)
        expect(klass::OUTPUT_FILE).to be_a(String)
      end
    end
  end
end

RSpec.describe Lowmu::Generators::Base do
  let(:slug_dir) { Dir.mktmpdir("lowmu_base_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }

  after { FileUtils.rm_rf(slug_dir) }

  describe "#ask_llm (private)" do
    context "when llm_config has no model key" do
      subject(:generator) { described_class.new(slug_dir, source_path, :post, {}, {}) }

      it "raises a helpful error" do
        expect { generator.send(:ask_llm, "test prompt") }
          .to raise_error(Lowmu::Error, /No model configured/)
      end
    end

    context "when llm_config has a model key" do
      subject(:generator) { described_class.new(slug_dir, source_path, :post, {}, {"model" => "claude-opus-4-6"}) }

      it "calls RubyLLM with the configured model" do
        mock_llm_response(content: "response")
        generator.send(:ask_llm, "test prompt")
        expect(RubyLLM).to have_received(:chat).with(model: "claude-opus-4-6")
      end

      it "raises a helpful error when the API key is missing" do
        allow(RubyLLM).to receive(:chat).and_raise(RubyLLM::ConfigurationError, "Missing configuration for Anthropic: anthropic_api_key")
        expect { generator.send(:ask_llm, "test prompt") }
          .to raise_error(Lowmu::Error, /ANTHROPIC_API_KEY/)
      end
    end
  end
end
