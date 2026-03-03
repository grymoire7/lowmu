require "spec_helper"

RSpec.describe Lowmu::Commands::Status do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:config) { instance_double(Lowmu::Config, content_dir: base_dir) }

  before do
    store = Lowmu::ContentStore.new(base_dir)
    FileUtils.mkdir_p(File.join(base_dir, "post-a"))
    FileUtils.mkdir_p(File.join(base_dir, "post-b"))
    store.write_status("post-a", {"substack" => {"status" => "generated"}})
    store.write_status("post-b", {"mastodon" => {"status" => "published"}})
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    context "without a slug" do
      it "returns an entry for every slug" do
        results = described_class.new(nil, config: config).call
        slugs = results.map { |r| r[:slug] }
        expect(slugs).to contain_exactly("post-a", "post-b")
      end
    end

    context "with a specific slug" do
      it "returns only that slug's entry" do
        results = described_class.new("post-a", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:slug]).to eq("post-a")
      end

      it "includes target statuses" do
        results = described_class.new("post-a", config: config).call
        expect(results.first[:targets].dig("substack", "status")).to eq("generated")
      end
    end
  end
end
