require "spec_helper"

RSpec.describe Lowmu::Generators::Hugo do
  let(:slug_dir) { Dir.mktmpdir("lowmu_hugo_test") }
  let(:target_config) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => "/tmp/hugo"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    subject(:output_file) do
      described_class.new(slug_dir, target_config, llm_config).generate
    end

    it "returns the output filename" do
      expect(output_file).to eq("hugo.md")
    end

    it "creates hugo.md in the slug directory" do
      output_file
      expect(File.exist?(File.join(slug_dir, "hugo.md"))).to be true
    end

    it "includes the title from front matter" do
      output_file
      content = File.read(File.join(slug_dir, "hugo.md"))
      expect(content).to include("title: My Test Post")
    end

    it "includes the post body content" do
      output_file
      content = File.read(File.join(slug_dir, "hugo.md"))
      expect(content).to include("content of my test post")
    end

    it "does not include publish_to in the Hugo front matter" do
      output_file
      content = File.read(File.join(slug_dir, "hugo.md"))
      expect(content).not_to include("publish_to")
    end
  end
end
