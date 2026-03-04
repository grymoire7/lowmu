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
    context "when slug is in the ignore list" do
      before do
        File.write(File.join(content_dir, "ignore.yml"), ["my-post"].to_yaml)
      end

      it "returns :ignore" do
        expect(slug_status.call).to eq(:ignore)
      end
    end

    context "when no generated files exist" do
      it "returns :pending" do
        expect(slug_status.call).to eq(:pending)
      end
    end

    context "when generated files exist and source is older than output" do
      before do
        store.ensure_slug_dir("my-post")
        output = File.join(store.slug_dir("my-post"), "hugo.md")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, source_file)
      end

      it "returns :generated" do
        expect(slug_status.call).to eq(:generated)
      end
    end

    context "when generated files exist but source is newer than output" do
      before do
        store.ensure_slug_dir("my-post")
        output = File.join(store.slug_dir("my-post"), "hugo.md")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, output)
      end

      it "returns :stale" do
        expect(slug_status.call).to eq(:stale)
      end
    end
  end
end
