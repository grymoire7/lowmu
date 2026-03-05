require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackLong do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_long_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "substack-long", "type" => "substack_long"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :long, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    it "returns the output filename" do
      expect(generator.generate).to eq("substack_long.md")
    end

    it "creates substack_long.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "substack_long.md"))).to be true
    end

    it "strips front matter from the output" do
      generator.generate
      output = File.read(File.join(slug_dir, "substack_long.md"))
      expect(output).not_to include("title:")
      expect(output).not_to include("---")
    end

    it "preserves the post body content" do
      generator.generate
      output = File.read(File.join(slug_dir, "substack_long.md"))
      expect(output).to include("content of my test post")
    end

    it "does not call the LLM" do
      expect(RubyLLM).not_to receive(:chat)
      generator.generate
    end
  end
end
