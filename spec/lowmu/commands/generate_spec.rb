require "spec_helper"

RSpec.describe Lowmu::Commands::Generate do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:slug) { "sample_post" }
  let(:slug_dir) { File.join(base_dir, slug) }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }
  let(:hugo_target) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => "/tmp"} }
  let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon"} }

  let(:config) do
    instance_double(Lowmu::Config,
      content_dir: base_dir,
      llm: llm_config,
      target_config: nil)
  end

  before do
    FileUtils.mkdir_p(slug_dir)
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
    store = Lowmu::ContentStore.new(base_dir)
    store.write_status(slug, {
      "tracyatteberry" => {"status" => "pending"},
      "mastodon" => {"status" => "pending"}
    })
    allow(config).to receive(:target_config).with("tracyatteberry").and_return(hugo_target)
    allow(config).to receive(:target_config).with("mastodon").and_return(mastodon_target)
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    context "without --target flag" do
      it "generates content for all pending targets" do
        mock_llm_response(content: "Mastodon post #ruby [URL]")
        results = described_class.new(slug, config: config).call
        expect(results.map { |r| r[:target] }).to contain_exactly("tracyatteberry", "mastodon")
      end

      it "updates status to generated for each target" do
        mock_llm_response(content: "post content")
        described_class.new(slug, config: config).call
        store = Lowmu::ContentStore.new(base_dir)
        expect(store.read_status(slug).dig("tracyatteberry", "status")).to eq("generated")
      end
    end

    context "with --target flag" do
      it "generates content only for the specified target" do
        results = described_class.new(slug, target: "tracyatteberry", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:target]).to eq("tracyatteberry")
      end

      it "raises for an unknown target" do
        expect {
          described_class.new(slug, target: "unknown", config: config).call
        }.to raise_error(Lowmu::Error, /not in publish_to/)
      end
    end

    context "with already-generated content" do
      before do
        store = Lowmu::ContentStore.new(base_dir)
        store.update_target_status(slug, "tracyatteberry", {"status" => "generated"})
      end

      it "raises without --force" do
        expect {
          described_class.new(slug, target: "tracyatteberry", config: config).call
        }.to raise_error(Lowmu::Error, /already generated/)
      end

      it "regenerates with --force" do
        result = described_class.new(slug, target: "tracyatteberry", force: true, config: config).call
        expect(result.first[:target]).to eq("tracyatteberry")
      end
    end

    it "raises if the slug does not exist" do
      expect {
        described_class.new("nonexistent", config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end
  end
end
