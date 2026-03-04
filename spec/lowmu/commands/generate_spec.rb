require "spec_helper"

RSpec.describe Lowmu::Commands::Generate do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo_content") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:post_dir) { File.join(hugo_content_dir, "posts", "my-post") }
  let(:source_path) { File.join(post_dir, "index.md") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }

  let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon"} }
  let(:hugo_target) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => "/tmp"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  let(:config) do
    instance_double(Lowmu::Config,
      hugo_content_dir: hugo_content_dir,
      content_dir: content_dir,
      llm: llm_config,
      targets: [mastodon_target, hugo_target])
  end

  before do
    FileUtils.mkdir_p(post_dir)
    FileUtils.cp("spec/fixtures/sample_post.md", source_path)
    allow(config).to receive(:target_config).with("mastodon").and_return(mastodon_target)
    allow(config).to receive(:target_config).with("tracyatteberry").and_return(hugo_target)
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  def mark_generated
    store.ensure_slug_dir("my-post")
    output = File.join(store.slug_dir("my-post"), "hugo.md")
    File.write(output, "generated content")
    past = Time.now - 60
    File.utime(past, past, source_path)
  end

  def mark_stale
    store.ensure_slug_dir("my-post")
    output = File.join(store.slug_dir("my-post"), "hugo.md")
    File.write(output, "generated content")
    past = Time.now - 60
    File.utime(past, past, output)
  end

  def mark_ignored(slug)
    File.write(File.join(content_dir, "ignore.yml"), [slug].to_yaml)
  end

  describe "#call" do
    context "with a pending slug" do
      it "generates content for all configured targets" do
        mock_llm_response(content: "Mastodon post #ruby [URL]")
        results = described_class.new(config: config).call
        expect(results.map { |r| r[:target] }).to contain_exactly("mastodon", "tracyatteberry")
      end

      it "includes the slug in each result" do
        mock_llm_response(content: "post")
        results = described_class.new(config: config).call
        expect(results.map { |r| r[:slug] }).to all(eq("my-post"))
      end

      it "creates the slug output directory" do
        mock_llm_response(content: "post")
        described_class.new(config: config).call
        expect(Dir.exist?(store.slug_dir("my-post"))).to be true
      end
    end

    context "with an already-generated (non-stale) slug" do
      before { mark_generated }

      it "skips it" do
        results = described_class.new(config: config).call
        expect(results).to be_empty
      end

      it "regenerates with --force" do
        mock_llm_response(content: "post")
        results = described_class.new(config: config, force: true).call
        expect(results).not_to be_empty
      end
    end

    context "with a stale slug" do
      before { mark_stale }

      it "does not generate without explicit slug or --force" do
        results = nil
        expect { results = described_class.new(config: config).call }.to output.to_stderr
        expect(results).to be_empty
      end

      it "warns about stale content to stderr" do
        expect { described_class.new(config: config).call }
          .to output(/stale.*my-post/i).to_stderr
      end

      it "generates when specific slug is given" do
        mock_llm_response(content: "post")
        results = described_class.new("my-post", config: config).call
        expect(results).not_to be_empty
      end

      it "generates with --force" do
        mock_llm_response(content: "post")
        results = described_class.new(config: config, force: true).call
        expect(results).not_to be_empty
      end
    end

    context "with an ignored slug" do
      before { mark_ignored("my-post") }

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
        results = described_class.new(target: "tracyatteberry", config: config).call
        expect(results.map { |r| r[:target] }).to contain_exactly("tracyatteberry")
      end

      it "raises for an unknown target" do
        expect {
          described_class.new(target: "unknown", config: config).call
        }.to raise_error(Lowmu::Error, /Unknown target/)
      end
    end
  end
end
