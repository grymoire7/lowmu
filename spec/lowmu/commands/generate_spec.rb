require "spec_helper"

RSpec.describe Lowmu::Commands::Generate do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo_content") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:post_dir) { File.join(hugo_content_dir, "posts", "my-post") }
  let(:note_dir) { File.join(hugo_content_dir, "notes") }
  let(:source_path) { File.join(post_dir, "index.md") }
  let(:note_source_path) { File.join(note_dir, "my-note.md") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }

  let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon_short"} }
  let(:newsletter_target) { {"name" => "substack-long", "type" => "substack_long"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  let(:config) do
    instance_double(Lowmu::Config,
      hugo_content_dir: hugo_content_dir,
      content_dir: content_dir,
      post_dirs: ["posts"],
      note_dirs: ["notes"],
      llm: llm_config,
      targets: [mastodon_target, newsletter_target])
  end

  before do
    FileUtils.mkdir_p(post_dir)
    FileUtils.cp("spec/fixtures/sample_post.md", source_path)
    allow(config).to receive(:target_config).with("mastodon").and_return(mastodon_target)
    allow(config).to receive(:target_config).with("substack-long").and_return(newsletter_target)
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  def mark_generated(key)
    store.ensure_slug_dir(key)
    output = File.join(store.slug_dir(key), "mastodon_short.md")
    File.write(output, "generated content")
    past = Time.now - 60
    File.utime(past, past, source_path)
  end

  def mark_stale(key)
    store.ensure_slug_dir(key)
    output = File.join(store.slug_dir(key), "mastodon_short.md")
    File.write(output, "generated content")
    past = Time.now - 60
    File.utime(past, past, output)
  end

  def mark_ignored(key)
    File.write(File.join(content_dir, "ignore.yml"), [key].to_yaml)
  end

  describe "#call" do
    context "with a pending post" do
      it "generates content for all configured targets" do
        mock_llm_response(content: "Generated output.")
        results = described_class.new(config: config).call
        expect(results.map { |r| r[:target] }).to contain_exactly("mastodon", "substack-long")
      end

      it "includes the compound key in each result" do
        mock_llm_response(content: "output")
        results = described_class.new(config: config).call
        expect(results.map { |r| r[:key] }).to all(eq("posts/my-post"))
      end

      it "creates the key output directory" do
        mock_llm_response(content: "output")
        described_class.new(config: config).call
        expect(Dir.exist?(store.slug_dir("posts/my-post"))).to be true
      end
    end

    context "with a pending note" do
      before do
        FileUtils.mkdir_p(note_dir)
        FileUtils.cp("spec/fixtures/sample_note.md", note_source_path)
      end

      it "skips long-form targets" do
        mock_llm_response(content: "Condensed #ruby")
        results = described_class.new(config: config).call
        note_results = results.select { |r| r[:key] == "notes/my-note" }
        expect(note_results.map { |r| r[:target] }).not_to include("substack-long")
      end

      it "includes short-form targets" do
        mock_llm_response(content: "Condensed #ruby")
        results = described_class.new(config: config).call
        note_results = results.select { |r| r[:key] == "notes/my-note" }
        expect(note_results.map { |r| r[:target] }).to include("mastodon")
      end
    end

    context "with an already-generated (non-stale) post" do
      before { mark_generated("posts/my-post") }

      it "skips it" do
        results = described_class.new(config: config).call
        expect(results).to be_empty
      end

      it "regenerates with --force" do
        mock_llm_response(content: "output")
        results = described_class.new(config: config, force: true).call
        expect(results).not_to be_empty
      end
    end

    context "with a stale post" do
      before { mark_stale("posts/my-post") }

      it "does not generate without explicit key or --force" do
        results = nil
        expect { results = described_class.new(config: config).call }.to output.to_stderr
        expect(results).to be_empty
      end

      it "warns about stale content to stderr" do
        expect { described_class.new(config: config).call }
          .to output(/stale.*posts\/my-post/i).to_stderr
      end

      it "generates when specific key is given" do
        mock_llm_response(content: "output")
        results = described_class.new("posts/my-post", config: config).call
        expect(results).not_to be_empty
      end

      it "generates with --force" do
        mock_llm_response(content: "output")
        results = described_class.new(config: config, force: true).call
        expect(results).not_to be_empty
      end
    end

    context "with an ignored post" do
      before { mark_ignored("posts/my-post") }

      it "skips it" do
        results = described_class.new(config: config).call
        expect(results).to be_empty
      end

      it "skips it even with --force" do
        results = described_class.new(config: config, force: true).call
        expect(results).to be_empty
      end
    end

    context "with --target filter" do
      it "generates only the specified target" do
        mock_llm_response(content: "output")
        results = described_class.new(target: "mastodon", config: config).call
        expect(results.map { |r| r[:target] }).to contain_exactly("mastodon")
      end

      it "raises for an unknown target" do
        expect {
          described_class.new(target: "unknown", config: config).call
        }.to raise_error(Lowmu::Error, /Unknown target/)
      end
    end
  end

  describe "#plan" do
    context "with a pending post" do
      it "returns one entry per applicable target" do
        results = described_class.new(config: config).plan
        expect(results.map { |r| r[:target] }).to contain_exactly("mastodon", "substack-long")
      end

      it "includes the compound key in each entry" do
        results = described_class.new(config: config).plan
        expect(results.map { |r| r[:key] }).to all(eq("posts/my-post"))
      end

      it "includes a generator instance in each entry" do
        results = described_class.new(config: config).plan
        expect(results.map { |r| r[:generator] }).to all(respond_to(:generate))
      end

      it "creates the key output directory" do
        described_class.new(config: config).plan
        expect(Dir.exist?(store.slug_dir("posts/my-post"))).to be true
      end
    end

    context "with an already-generated post" do
      before { mark_generated("posts/my-post") }

      it "returns empty" do
        expect(described_class.new(config: config).plan).to be_empty
      end
    end
  end
end
