require "spec_helper"

RSpec.describe Lowmu::Commands::Status do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo_content") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }

  let(:config) do
    instance_double(Lowmu::Config,
      hugo_content_dir: hugo_content_dir,
      content_dir: content_dir)
  end

  let(:source_a) { File.join(hugo_content_dir, "posts", "post-a", "index.md") }
  let(:source_b) { File.join(hugo_content_dir, "notes", "post-b.md") }

  before do
    FileUtils.mkdir_p(File.join(hugo_content_dir, "posts", "post-a"))
    File.write(source_a, "---\ntitle: Post A\n---\nContent.")
    FileUtils.mkdir_p(File.join(hugo_content_dir, "notes"))
    File.write(source_b, "---\ntitle: Post B\n---\nContent.")
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  describe "#call" do
    context "without a slug filter" do
      it "returns an entry for every discovered slug" do
        results = described_class.new(nil, config: config).call
        expect(results.map { |r| r[:slug] }).to contain_exactly("post-a", "post-b")
      end

      it "reports :pending for new slugs" do
        results = described_class.new(nil, config: config).call
        expect(results.map { |r| r[:status] }).to all(eq(:pending))
      end
    end

    context "with a specific slug filter" do
      it "returns only that slug's entry" do
        results = described_class.new("post-a", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:slug]).to eq("post-a")
      end
    end

    context "with a generated slug" do
      before do
        store.ensure_slug_dir("post-a")
        output = File.join(store.slug_dir("post-a"), "hugo.md")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, source_a)
      end

      it "returns :generated status" do
        results = described_class.new("post-a", config: config).call
        expect(results.first[:status]).to eq(:generated)
      end
    end

    context "with a stale slug" do
      before do
        store.ensure_slug_dir("post-a")
        output = File.join(store.slug_dir("post-a"), "hugo.md")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, output)
      end

      it "returns :stale status" do
        results = described_class.new("post-a", config: config).call
        expect(results.first[:status]).to eq(:stale)
      end
    end

    context "with an ignored slug" do
      before do
        File.write(File.join(content_dir, "ignore.yml"), ["post-a"].to_yaml)
      end

      it "returns :ignore status" do
        results = described_class.new("post-a", config: config).call
        expect(results.first[:status]).to eq(:ignore)
      end
    end
  end
end
