# Filesystem-Derived Status + Ignore File Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace per-slug `status.yml` metadata with filesystem mtime-derived status, and add an `ignore.yml` file so users can exclude backlog posts from generation.

**Architecture:** `ContentStore` gains `ignore_slugs` (reads `<content_dir>/ignore.yml`) and loses its status read/write methods. `SlugStatus` checks the ignore list first, then derives status from whether generated files exist and their mtimes relative to the source file. `Commands::Generate` drops the `write_status` call — generated file mtimes become the implicit record.

**Tech Stack:** Ruby, RSpec, YAML stdlib, FileUtils

---

### Task 1: Add `ContentStore#ignore_slugs`, remove dead status methods

**Files:**
- Modify: `spec/lowmu/content_store_spec.rb`
- Modify: `lib/lowmu/content_store.rb`

**Step 1: Write failing tests for `ignore_slugs`**

Replace the `#write_status and #read_status` and `#generated_at` describe blocks in `spec/lowmu/content_store_spec.rb` with a new `#ignore_slugs` block. Remove those old describe blocks entirely.

```ruby
describe "#ignore_slugs" do
  it "returns empty array when ignore.yml does not exist" do
    expect(store.ignore_slugs).to eq([])
  end

  it "returns slugs listed in ignore.yml" do
    File.write(File.join(base_dir, "ignore.yml"), ["post-a", "post-b"].to_yaml)
    expect(store.ignore_slugs).to contain_exactly("post-a", "post-b")
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/content_store_spec.rb -e "ignore_slugs" --format documentation
```

Expected: FAIL with `undefined method 'ignore_slugs'`

**Step 3: Update `ContentStore`**

In `lib/lowmu/content_store.rb`:
- Remove the `STATUS_FILE` constant
- Remove `write_status`, `read_status`, `generated_at`
- Add `ignore_slugs`:

```ruby
IGNORE_FILE = "ignore.yml"

def ignore_slugs
  path = File.join(base_dir, IGNORE_FILE)
  return [] unless File.exist?(path)
  YAML.safe_load_file(path) || []
end
```

**Step 4: Run the full content store spec**

```bash
bundle exec rspec spec/lowmu/content_store_spec.rb --format documentation
```

Expected: all pass (the old write_status/generated_at tests are gone, new ones pass)

**Step 5: Commit**

```bash
git add spec/lowmu/content_store_spec.rb lib/lowmu/content_store.rb
git commit -m "refactor: replace ContentStore status methods with ignore_slugs"
```

---

### Task 2: Rewrite `SlugStatus` to use filesystem mtimes + support `:ignore`

**Files:**
- Modify: `spec/lowmu/slug_status_spec.rb`
- Modify: `lib/lowmu/slug_status.rb`

**Step 1: Rewrite the spec**

Replace all of `spec/lowmu/slug_status_spec.rb`:

```ruby
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
```

**Step 2: Run to verify failures**

```bash
bundle exec rspec spec/lowmu/slug_status_spec.rb --format documentation
```

Expected: FAIL — the ignore and mtime-based tests fail, pending still passes by coincidence (no dir = no status file = :pending still works for now)

**Step 3: Rewrite `SlugStatus#call`**

Replace the body of `call` in `lib/lowmu/slug_status.rb`:

```ruby
def call
  return :ignore if @content_store.ignore_slugs.include?(@slug)

  slug_dir = @content_store.slug_dir(@slug)
  return :pending unless Dir.exist?(slug_dir)

  files = Dir.children(slug_dir).map { |f| File.join(slug_dir, f) }.select { |f| File.file?(f) }
  return :pending if files.empty?

  oldest_generated = files.map { |f| File.mtime(f) }.min
  (File.mtime(@source_path) > oldest_generated) ? :stale : :generated
end
```

**Step 4: Run slug status spec**

```bash
bundle exec rspec spec/lowmu/slug_status_spec.rb --format documentation
```

Expected: all 4 examples pass

**Step 5: Commit**

```bash
git add spec/lowmu/slug_status_spec.rb lib/lowmu/slug_status.rb
git commit -m "refactor: derive SlugStatus from filesystem mtimes; add :ignore support"
```

---

### Task 3: Update `Commands::Generate` — remove `write_status`, skip `:ignore` slugs

**Files:**
- Modify: `spec/lowmu/commands/generate_spec.rb`
- Modify: `lib/lowmu/commands/generate.rb`

**Step 1: Rewrite generate spec helpers and add ignore test**

Replace the `mark_generated` helper and add `mark_stale` and `mark_ignored` helpers. Replace the "writes generated_at to status" test with an `:ignore` context. The full updated spec:

```ruby
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
```

**Step 2: Run to verify failures**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb --format documentation
```

Expected: the two new ignore examples fail; others may fail due to `write_status` being gone

**Step 3: Update `Commands::Generate`**

In `lib/lowmu/commands/generate.rb`, make two changes:

1. In `should_generate?`, add ignore check at the top:

```ruby
def should_generate?(item)
  status = slug_status(item)
  return false if status == :ignore
  return true if @force
  if @slug_filter
    status == :pending || status == :stale
  else
    status == :pending
  end
end
```

2. In `generate_slug`, remove the `@store.write_status(...)` call and the `targets_generated` hash. The method becomes:

```ruby
def generate_slug(item)
  @store.ensure_slug_dir(item[:slug])

  resolve_targets.map do |target_name|
    target_config = @config.target_config(target_name)
    generator_class = GENERATOR_MAP.fetch(target_config["type"]) do
      raise Error, "Unknown target type: #{target_config["type"]}"
    end

    output_file = generator_class.new(
      @store.slug_dir(item[:slug]),
      item[:source_path],
      target_config,
      @config.llm
    ).generate

    {slug: item[:slug], target: target_name, file: output_file}
  end
end
```

**Step 4: Run generate spec**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb --format documentation
```

Expected: all examples pass

**Step 5: Commit**

```bash
git add spec/lowmu/commands/generate_spec.rb lib/lowmu/commands/generate.rb
git commit -m "feat: skip ignored slugs in generate; remove write_status call"
```

---

### Task 4: Update `Commands::Status` spec to use file-based state + add ignore test

**Files:**
- Modify: `spec/lowmu/commands/status_spec.rb`

**Step 1: Rewrite the status spec**

Replace `spec/lowmu/commands/status_spec.rb`:

```ruby
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
```

**Step 2: Run to verify the new ignore example fails**

```bash
bundle exec rspec spec/lowmu/commands/status_spec.rb --format documentation
```

Expected: the `:ignore` context fails; all others pass (since SlugStatus already handles the new logic)

**Step 3: No implementation changes needed**

`Commands::Status` already passes items through `SlugStatus`, which now returns `:ignore`. No code changes required.

**Step 4: Run full spec suite**

```bash
bundle exec rspec --format documentation
```

Expected: all examples pass

**Step 5: Commit**

```bash
git add spec/lowmu/commands/status_spec.rb
git commit -m "test: update status spec to use file mtimes; add ignore coverage"
```
