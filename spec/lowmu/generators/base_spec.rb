require "spec_helper"

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
    end
  end
end
