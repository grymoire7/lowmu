require "spec_helper"

RSpec.describe Lowmu::SlugStatus do
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }
  let(:source_file) do
    path = File.join(content_dir, "source.md")
    File.write(path, "content")
    path
  end

  subject(:slug_status) { described_class.new("my-post", source_file, store) }

  after { FileUtils.rm_rf(content_dir) }

  describe "#call" do
    context "when no status.yml exists" do
      it "returns :pending" do
        expect(slug_status.call).to eq(:pending)
      end
    end

    context "when generated_at is in the future (source is older)" do
      before do
        store.ensure_slug_dir("my-post")
        store.write_status("my-post", {
          "generated_at" => (Time.now + 60).utc.iso8601
        })
      end

      it "returns :generated" do
        expect(slug_status.call).to eq(:generated)
      end
    end

    context "when generated_at is in the past (source is newer)" do
      before do
        store.ensure_slug_dir("my-post")
        store.write_status("my-post", {
          "generated_at" => (Time.now - 60).utc.iso8601
        })
      end

      it "returns :stale" do
        expect(slug_status.call).to eq(:stale)
      end
    end
  end
end
