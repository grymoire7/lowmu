# Content Type Routing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix HugoScanner to only scan configured dirs, carry content type (post/note) through the pipeline as a compound key (`section/slug`), and filter generator targets by form factor so notes never produce long-form output.

**Architecture:** `HugoScanner` returns items tagged with `{slug:, section:, content_type:, source_path:, key:}`. The compound `key` (`"posts/jojo"`) replaces bare slug everywhere: ContentStore paths, ignore.yml, CLI output, and status filtering. Each generator declares `FORM = :long` or `:short`; the Generate command skips `:long` targets when `content_type == :note`.

**Tech Stack:** Ruby, RSpec (TDD), StandardRB (run after each task), Zeitwerk (auto-load — file names must match class names exactly)

---

### Task 1: Config — post_dirs and note_dirs

**Files:**
- Modify: `lib/lowmu/config.rb`
- Modify: `spec/lowmu/config_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/lowmu/config_spec.rb` inside `RSpec.describe Lowmu::Config do`:

```ruby
describe "#post_dirs" do
  it "defaults to ['posts']" do
    config = described_class.new({"hugo_content_dir" => "/tmp/hugo"})
    expect(config.post_dirs).to eq(["posts"])
  end

  it "returns configured value" do
    config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "post_dirs" => ["posts", "articles"]})
    expect(config.post_dirs).to eq(["posts", "articles"])
  end
end

describe "#note_dirs" do
  it "defaults to ['notes']" do
    config = described_class.new({"hugo_content_dir" => "/tmp/hugo"})
    expect(config.note_dirs).to eq(["notes"])
  end

  it "returns configured value" do
    config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "note_dirs" => ["notes", "microblog"]})
    expect(config.note_dirs).to eq(["notes", "microblog"])
  end
end
```

**Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/lowmu/config_spec.rb
```
Expected: fail with `undefined method 'post_dirs'`

**Step 3: Implement**

In `lib/lowmu/config.rb`:
- Add `post_dirs` and `note_dirs` to `attr_reader`
- In `initialize`, add:
  ```ruby
  @post_dirs = data.fetch("post_dirs", ["posts"])
  @note_dirs = data.fetch("note_dirs", ["notes"])
  ```

**Step 4: Run to confirm passing**

```bash
bundle exec rspec spec/lowmu/config_spec.rb
```
Expected: all pass

**Step 5: Commit**

```bash
git add lib/lowmu/config.rb spec/lowmu/config_spec.rb
git commit -m "feat: add post_dirs and note_dirs to Config"
```

---

### Task 2: HugoScanner — compound key, content_type, filtered scanning

**Files:**
- Modify: `lib/lowmu/hugo_scanner.rb`
- Modify: `spec/lowmu/hugo_scanner_spec.rb`

**Step 1: Rewrite the spec**

Replace the entire contents of `spec/lowmu/hugo_scanner_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::HugoScanner do
  let(:hugo_dir) { Dir.mktmpdir("hugo_content") }

  after { FileUtils.rm_rf(hugo_dir) }

  def write_md(rel_path, front_matter = {})
    full = File.join(hugo_dir, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    fm = front_matter.map { |k, v| "#{k}: #{v}" }.join("\n")
    File.write(full, "---\n#{fm}\n---\nContent.")
    full
  end

  def scanner
    described_class.new(hugo_dir, post_dirs: ["posts"], note_dirs: ["notes"])
  end

  describe "#scan" do
    it "derives slug from parent directory name for index.md files" do
      write_md("posts/my-post/index.md", title: "My Post")
      expect(scanner.scan.map { |r| r[:slug] }).to include("my-post")
    end

    it "derives slug from filename for non-index files" do
      write_md("notes/quick-tip.md", title: "Quick Tip")
      expect(scanner.scan.map { |r| r[:slug] }).to include("quick-tip")
    end

    it "uses front matter slug when present" do
      write_md("posts/long-dirname/index.md", title: "Post", slug: "custom")
      slugs = scanner.scan.map { |r| r[:slug] }
      expect(slugs).to include("custom")
      expect(slugs).not_to include("long-dirname")
    end

    it "includes the full source_path for each entry" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:source_path]).to eq(File.join(hugo_dir, "posts/my-post/index.md"))
    end

    it "tags items from post_dirs with content_type :post" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:content_type]).to eq(:post)
    end

    it "tags items from note_dirs with content_type :note" do
      write_md("notes/quick-tip.md")
      result = scanner.scan.first
      expect(result[:content_type]).to eq(:note)
    end

    it "sets section to the directory name" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:section]).to eq("posts")
    end

    it "sets key to section/slug" do
      write_md("posts/my-post/index.md")
      result = scanner.scan.first
      expect(result[:key]).to eq("posts/my-post")
    end

    it "excludes directories not in post_dirs or note_dirs" do
      write_md("posts/post-a/index.md")
      write_md("portfolio/jojo/index.md")
      write_md("about/me.md")
      results = scanner.scan
      expect(results.length).to eq(1)
      expect(results.first[:slug]).to eq("post-a")
    end

    it "scans both post_dirs and note_dirs" do
      write_md("posts/post-a/index.md")
      write_md("posts/post-b/index.md")
      write_md("notes/note-a.md")
      expect(scanner.scan.length).to eq(3)
    end

    it "returns empty array when hugo_content_dir has no matching markdown files" do
      expect(scanner.scan).to eq([])
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/lowmu/hugo_scanner_spec.rb
```
Expected: multiple failures

**Step 3: Rewrite the implementation**

Replace `lib/lowmu/hugo_scanner.rb`:

```ruby
module Lowmu
  class HugoScanner
    def initialize(hugo_content_dir, post_dirs: ["posts"], note_dirs: ["notes"])
      @hugo_content_dir = File.expand_path(hugo_content_dir)
      @post_dirs = post_dirs
      @note_dirs = note_dirs
    end

    def scan
      results = []
      @post_dirs.each { |dir| results += scan_section(dir, :post) }
      @note_dirs.each { |dir| results += scan_section(dir, :note) }
      results
    end

    private

    def scan_section(section, content_type)
      full_dir = File.join(@hugo_content_dir, section)
      return [] unless Dir.exist?(full_dir)

      Dir.glob("**/*.md", base: full_dir).map do |rel_path|
        full_path = File.join(full_dir, rel_path)
        slug = derive_slug(full_path)
        {
          slug: slug,
          section: section,
          content_type: content_type,
          source_path: full_path,
          key: "#{section}/#{slug}"
        }
      end
    end

    def derive_slug(path)
      content = File.read(path)
      loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
      parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(content)

      fm = parsed.front_matter || {}
      return fm["slug"] if fm["slug"]

      if File.basename(path) == "index.md"
        File.basename(File.dirname(path))
      else
        File.basename(path, ".md")
      end
    end
  end
end
```

**Step 4: Run to confirm passing**

```bash
bundle exec rspec spec/lowmu/hugo_scanner_spec.rb
```
Expected: all pass

**Step 5: Run full suite to check for regressions**

```bash
bundle exec rspec
```
Expected: some failures in status_spec and generate_spec (they use old scanner constructor) — that's expected and will be fixed in later tasks. All other specs should pass.

**Step 6: Commit**

```bash
git add lib/lowmu/hugo_scanner.rb spec/lowmu/hugo_scanner_spec.rb
git commit -m "feat: HugoScanner returns compound key and content_type"
```

---

### Task 3: ContentStore — compound key paths

**Files:**
- Modify: `lib/lowmu/content_store.rb`
- Modify: `spec/lowmu/content_store_spec.rb`

The compound key `"posts/my-post"` is just a path segment. `File.join(base_dir, "generated", "posts/my-post")` already works correctly in Ruby. The `slugs` method needs to return compound keys by scanning two levels deep.

**Step 1: Update the spec**

Replace `spec/lowmu/content_store_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::ContentStore do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:store) { described_class.new(base_dir) }

  after { FileUtils.rm_rf(base_dir) }

  describe "#slug_exists?" do
    it "returns false when key directory does not exist" do
      expect(store.slug_exists?("posts/my-post")).to be false
    end

    it "returns true after ensure_slug_dir is called" do
      store.ensure_slug_dir("posts/my-post")
      expect(store.slug_exists?("posts/my-post")).to be true
    end
  end

  describe "#ensure_slug_dir" do
    it "creates the key directory under generated/" do
      store.ensure_slug_dir("posts/my-post")
      expect(Dir.exist?(File.join(base_dir, "generated", "posts", "my-post"))).to be true
    end

    it "is idempotent" do
      store.ensure_slug_dir("posts/my-post")
      expect { store.ensure_slug_dir("posts/my-post") }.not_to raise_error
    end
  end

  describe "#ignore_slugs" do
    it "returns empty array when ignore.yml does not exist" do
      expect(store.ignore_slugs).to eq([])
    end

    it "returns compound keys listed in ignore.yml" do
      File.write(File.join(base_dir, "ignore.yml"), ["posts/post-a", "notes/note-b"].to_yaml)
      expect(store.ignore_slugs).to contain_exactly("posts/post-a", "notes/note-b")
    end
  end

  describe "#slugs" do
    it "returns all compound keys sorted" do
      store.ensure_slug_dir("posts/post-b")
      store.ensure_slug_dir("posts/post-a")
      store.ensure_slug_dir("notes/note-a")
      expect(store.slugs).to eq(["notes/note-a", "posts/post-a", "posts/post-b"])
    end

    it "returns empty array when base_dir does not exist" do
      expect(described_class.new("/nonexistent/path").slugs).to eq([])
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/lowmu/content_store_spec.rb
```
Expected: failures on `slugs` (returns flat names, not compound) and updated test strings

**Step 3: Update the implementation**

Replace `lib/lowmu/content_store.rb`:

```ruby
module Lowmu
  class ContentStore
    IGNORE_FILE = "ignore.yml"

    attr_reader :base_dir

    def initialize(base_dir)
      @base_dir = File.expand_path(base_dir)
    end

    def slug_dir(key)
      File.join(base_dir, "generated", key)
    end

    def slug_exists?(key)
      Dir.exist?(slug_dir(key))
    end

    def ensure_slug_dir(key)
      FileUtils.mkdir_p(slug_dir(key))
    end

    def ignore_slugs
      path = File.join(base_dir, IGNORE_FILE)
      return [] unless File.exist?(path)
      YAML.safe_load_file(path) || []
    end

    def slugs
      generated_dir = File.join(base_dir, "generated")
      return [] unless Dir.exist?(generated_dir)
      Dir.children(generated_dir)
        .select { |section| Dir.exist?(File.join(generated_dir, section)) }
        .flat_map do |section|
          section_dir = File.join(generated_dir, section)
          Dir.children(section_dir)
            .select { |f| Dir.exist?(File.join(section_dir, f)) }
            .map { |slug| "#{section}/#{slug}" }
        end
        .sort
    end
  end
end
```

**Step 4: Run to confirm passing**

```bash
bundle exec rspec spec/lowmu/content_store_spec.rb
```
Expected: all pass

**Step 5: Commit**

```bash
git add lib/lowmu/content_store.rb spec/lowmu/content_store_spec.rb
git commit -m "feat: ContentStore uses compound key (section/slug) for paths"
```

---

### Task 4: SlugStatus — compound key

**Files:**
- Modify: `lib/lowmu/slug_status.rb`
- Modify: `spec/lowmu/slug_status_spec.rb`

**Step 1: Update the spec**

Replace `spec/lowmu/slug_status_spec.rb`:

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

  subject(:slug_status) { described_class.new("posts/my-post", source_file, store) }

  after { FileUtils.rm_rf(content_dir) }

  describe "#call" do
    context "when key is in the ignore list" do
      before do
        File.write(File.join(content_dir, "ignore.yml"), ["posts/my-post"].to_yaml)
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
        store.ensure_slug_dir("posts/my-post")
        output = File.join(store.slug_dir("posts/my-post"), "mastodon.txt")
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
        store.ensure_slug_dir("posts/my-post")
        output = File.join(store.slug_dir("posts/my-post"), "mastodon.txt")
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

**Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/lowmu/slug_status_spec.rb
```
Expected: failures (ignore list uses bare slug, generated dir path is wrong)

**Step 3: Update the implementation**

`lib/lowmu/slug_status.rb` — rename `@slug` to `@key` throughout:

```ruby
module Lowmu
  class SlugStatus
    def initialize(key, source_path, content_store)
      @key = key
      @source_path = source_path
      @content_store = content_store
    end

    def call
      return :ignore if @content_store.ignore_slugs.include?(@key)

      slug_dir = @content_store.slug_dir(@key)
      return :pending unless Dir.exist?(slug_dir)

      files = Dir.children(slug_dir).map { |f| File.join(slug_dir, f) }.select { |f| File.file?(f) }
      return :pending if files.empty?

      oldest_generated = files.map { |f| File.mtime(f) }.min
      (File.mtime(@source_path) > oldest_generated) ? :stale : :generated
    end
  end
end
```

**Step 4: Run to confirm passing**

```bash
bundle exec rspec spec/lowmu/slug_status_spec.rb
```
Expected: all pass

**Step 5: Commit**

```bash
git add lib/lowmu/slug_status.rb spec/lowmu/slug_status_spec.rb
git commit -m "feat: SlugStatus uses compound key"
```

---

### Task 5: Commands::Status — compound key

**Files:**
- Modify: `lib/lowmu/commands/status.rb`
- Modify: `spec/lowmu/commands/status_spec.rb`

**Step 1: Update the spec**

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
      content_dir: content_dir,
      post_dirs: ["posts"],
      note_dirs: ["notes"])
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
    context "without a key filter" do
      it "returns an entry for every discovered item" do
        results = described_class.new(nil, config: config).call
        expect(results.map { |r| r[:key] }).to contain_exactly("posts/post-a", "notes/post-b")
      end

      it "reports :pending for new items" do
        results = described_class.new(nil, config: config).call
        expect(results.map { |r| r[:status] }).to all(eq(:pending))
      end
    end

    context "with a specific key filter" do
      it "returns only that item's entry" do
        results = described_class.new("posts/post-a", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:key]).to eq("posts/post-a")
      end
    end

    context "with a generated item" do
      before do
        store.ensure_slug_dir("posts/post-a")
        output = File.join(store.slug_dir("posts/post-a"), "mastodon.txt")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, source_a)
      end

      it "returns :generated status" do
        results = described_class.new("posts/post-a", config: config).call
        expect(results.first[:status]).to eq(:generated)
      end
    end

    context "with a stale item" do
      before do
        store.ensure_slug_dir("posts/post-a")
        output = File.join(store.slug_dir("posts/post-a"), "mastodon.txt")
        File.write(output, "generated content")
        past = Time.now - 60
        File.utime(past, past, output)
      end

      it "returns :stale status" do
        results = described_class.new("posts/post-a", config: config).call
        expect(results.first[:status]).to eq(:stale)
      end
    end

    context "with an ignored item" do
      before do
        File.write(File.join(content_dir, "ignore.yml"), ["posts/post-a"].to_yaml)
      end

      it "returns :ignore status" do
        results = described_class.new("posts/post-a", config: config).call
        expect(results.first[:status]).to eq(:ignore)
      end
    end
  end
end
```

**Step 2: Run to confirm failure**

```bash
bundle exec rspec spec/lowmu/commands/status_spec.rb
```
Expected: failures

**Step 3: Update the implementation**

Replace `lib/lowmu/commands/status.rb`:

```ruby
module Lowmu
  module Commands
    class Status
      def initialize(key = nil, config:)
        @key_filter = key
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter

        items.map do |item|
          status = SlugStatus.new(item[:key], item[:source_path], @store).call
          {key: item[:key], status: status}
        end
      end
    end
  end
end
```

**Step 4: Run to confirm passing**

```bash
bundle exec rspec spec/lowmu/commands/status_spec.rb
```
Expected: all pass

**Step 5: Commit**

```bash
git add lib/lowmu/commands/status.rb spec/lowmu/commands/status_spec.rb
git commit -m "feat: Status command uses compound key"
```

---

### Task 6: Generators::Base — add content_type parameter; update all existing generator tests

`content_type` becomes the 3rd positional arg: `(slug_dir, source_path, content_type, target_config, llm_config)`.

**Files:**
- Modify: `lib/lowmu/generators/base.rb`
- Modify: `spec/lowmu/generators/base_spec.rb`
- Modify: `spec/lowmu/generators/mastodon_spec.rb`
- Modify: `spec/lowmu/generators/substack_spec.rb`
- Modify: `spec/lowmu/generators/linkedin_spec.rb`
- Modify: `lib/lowmu/generators/mastodon.rb` (accept arg, behavior unchanged for now)
- Modify: `lib/lowmu/generators/substack.rb` (accept arg, behavior unchanged for now)
- Modify: `lib/lowmu/generators/linkedin.rb` (accept arg, behavior unchanged for now)

**Step 1: Update base_spec**

In `spec/lowmu/generators/base_spec.rb`, change both `described_class.new(slug_dir, source_path, {}, {})` calls to `described_class.new(slug_dir, source_path, :post, {}, {})`:

```ruby
# line 11:
subject(:generator) { described_class.new(slug_dir, source_path, :post, {}, {}) }

# line 20:
subject(:generator) { described_class.new(slug_dir, source_path, :post, {}, {"model" => "claude-opus-4-6"}) }
```

**Step 2: Update base implementation**

In `lib/lowmu/generators/base.rb`, add `content_type` as 3rd arg:

```ruby
def initialize(slug_dir, source_path, content_type, target_config, llm_config)
  @slug_dir = slug_dir
  @source_path = source_path
  @content_type = content_type
  @target_config = target_config
  @llm_config = llm_config
end
```

**Step 3: Update mastodon_spec helper**

In `spec/lowmu/generators/mastodon_spec.rb`, change the `generator` helper:

```ruby
def generator(source, content_type = :post)
  described_class.new(slug_dir, source, content_type, target_config, llm_config)
end
```

Also update the note contexts to pass `:note`:
- `context "with type: note and content within 500 chars"` — change call to `generator(source_path, :note)`
- `context "with type: note and content over 500 chars"` — change call to `generator(source_path, :note)`

**Step 4: Update mastodon implementation to accept new signature**

In `lib/lowmu/generators/mastodon.rb`, the superclass `initialize` now takes `content_type`, so existing calls will break. The class doesn't define its own `initialize`, so it inherits Base's. No change needed in mastodon.rb itself — it inherits the new signature automatically.

**Step 5: Update substack_spec helper**

In `spec/lowmu/generators/substack_spec.rb`, change the `generator` helper:

```ruby
def generator(source, content_type = :post)
  described_class.new(slug_dir, source, content_type, target_config, llm_config)
end
```

Update the `context "with type: note"` block to pass `:note`:
- All calls inside that context: `generator(source_path, :note)`

**Step 6: Update substack implementation**

`lib/lowmu/generators/substack.rb` inherits Base's `initialize`. No changes needed — it still reads front matter for type detection (will be replaced entirely in Task 8).

**Step 7: Update linkedin_spec**

In `spec/lowmu/generators/linkedin_spec.rb`, update all constructor calls:

```ruby
# Change all:
described_class.new(slug_dir, source_path, target_config, llm_config)
# To:
described_class.new(slug_dir, source_path, :post, target_config, llm_config)
```

**Step 8: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing (mastodon/substack/linkedin behavior unchanged, just new arg)

**Step 9: Commit**

```bash
git add lib/lowmu/generators/base.rb spec/lowmu/generators/base_spec.rb \
        lib/lowmu/generators/mastodon.rb spec/lowmu/generators/mastodon_spec.rb \
        lib/lowmu/generators/substack.rb spec/lowmu/generators/substack_spec.rb \
        lib/lowmu/generators/linkedin.rb spec/lowmu/generators/linkedin_spec.rb
git commit -m "refactor: add content_type parameter to Generators::Base"
```

---

### Task 7: Remove Generators::Hugo

**Files:**
- Delete: `lib/lowmu/generators/hugo.rb`
- Delete: `spec/lowmu/generators/hugo_spec.rb`
- Modify: `lib/lowmu/commands/generate.rb` (remove from GENERATOR_MAP)

**Step 1: Delete files**

```bash
rm lib/lowmu/generators/hugo.rb spec/lowmu/generators/hugo_spec.rb
```

**Step 2: Remove from GENERATOR_MAP**

In `lib/lowmu/commands/generate.rb`, remove the `"hugo" => Generators::Hugo` entry from `GENERATOR_MAP`.

**Step 3: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing (hugo_spec is gone, no other tests reference Hugo generator)

**Step 4: Commit**

```bash
git add -u
git commit -m "feat: remove Hugo generator (blog is input, not output)"
```

---

### Task 8: Add Generators::SubstackNewsletter and SubstackNote (replace Substack)

**Files:**
- Create: `lib/lowmu/generators/substack_newsletter.rb`
- Create: `lib/lowmu/generators/substack_note.rb`
- Create: `spec/lowmu/generators/substack_newsletter_spec.rb`
- Create: `spec/lowmu/generators/substack_note_spec.rb`
- Delete: `lib/lowmu/generators/substack.rb`
- Delete: `spec/lowmu/generators/substack_spec.rb`
- Modify: `lib/lowmu/commands/generate.rb` (update GENERATOR_MAP)

**Step 1: Write SubstackNewsletter spec**

Create `spec/lowmu/generators/substack_newsletter_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackNewsletter do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_newsletter_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "substack-newsletter", "type" => "substack_newsletter"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :post, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    before { mock_llm_response(content: "Reformatted newsletter content.") }

    it "returns the output filename" do
      expect(generator.generate).to eq("substack_newsletter.md")
    end

    it "creates substack_newsletter.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "substack_newsletter.md"))).to be true
    end

    it "calls the LLM once" do
      mock_chat = mock_llm_response(content: "Newsletter content.")
      generator.generate
      expect(mock_chat).to have_received(:ask).once
    end

    it "sends post content to LLM" do
      mock_chat = mock_llm_response(content: "output")
      generator.generate
      expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
    end
  end
end
```

**Step 2: Write SubstackNote spec**

Create `spec/lowmu/generators/substack_note_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackNote do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_note_test") }
  let(:target_config) { {"name" => "substack-note", "type" => "substack_note"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with content_type :post" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Short note announcing post. [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :post).generate).to eq("substack_note.md")
      end

      it "creates substack_note.md" do
        generator(source_path, :post).generate
        expect(File.exist?(File.join(slug_dir, "substack_note.md"))).to be true
      end

      it "calls the LLM to generate a note from the post" do
        mock_chat = mock_llm_response(content: "Note about post. [URL]")
        generator(source_path, :post).generate
        expect(mock_chat).to have_received(:ask).once
      end

      it "sends post content to LLM" do
        mock_chat = mock_llm_response(content: "output")
        generator(source_path, :post).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
      end
    end

    context "with content_type :note" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      it "returns the output filename" do
        expect(generator(source_path, :note).generate).to eq("substack_note.md")
      end

      it "creates substack_note.md" do
        generator(source_path, :note).generate
        expect(File.exist?(File.join(slug_dir, "substack_note.md"))).to be true
      end

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        generator(source_path, :note).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body without front matter" do
        generator(source_path, :note).generate
        content = File.read(File.join(slug_dir, "substack_note.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end
  end
end
```

**Step 3: Run to confirm failures**

```bash
bundle exec rspec spec/lowmu/generators/substack_newsletter_spec.rb spec/lowmu/generators/substack_note_spec.rb
```
Expected: fail with `uninitialized constant`

**Step 4: Implement SubstackNewsletter**

Create `lib/lowmu/generators/substack_newsletter.rb`:

```ruby
module Lowmu
  module Generators
    class SubstackNewsletter < Base
      FORM = :long
      OUTPUT_FILE = "substack_newsletter.md"

      PROMPT = <<~PROMPT
        Reformat the following markdown blog post for publication on Substack.
        Keep the full content intact. Ensure the markdown is clean and readable.
        Remove any front matter — return only the body content with no front matter at all.
        Preserve the author's voice and tone exactly.

        Original post:
        %s

        Return only the formatted markdown content.
      PROMPT

      def generate
        content = ask_llm(PROMPT % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 5: Implement SubstackNote**

Create `lib/lowmu/generators/substack_note.rb`:

```ruby
module Lowmu
  module Generators
    class SubstackNote < Base
      FORM = :short
      OUTPUT_FILE = "substack_note.md"

      NOTE_FROM_POST_PROMPT = <<~PROMPT
        Write a short Substack note announcing the following blog post. Requirements:
        - Should be 2-4 sentences
        - Capture the key hook or insight from the post
        - Use a conversational, authentic tone
        - End with [URL] as a placeholder for the post URL

        Blog post:
        %s

        Return only the note text.
      PROMPT

      def generate
        if @content_type == :note
          loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
          parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
          write_output(OUTPUT_FILE, parsed.content.strip)
        else
          content = ask_llm(NOTE_FROM_POST_PROMPT % original_content)
          write_output(OUTPUT_FILE, content)
        end
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 6: Run new specs**

```bash
bundle exec rspec spec/lowmu/generators/substack_newsletter_spec.rb spec/lowmu/generators/substack_note_spec.rb
```
Expected: all pass

**Step 7: Delete old Substack files**

```bash
rm lib/lowmu/generators/substack.rb spec/lowmu/generators/substack_spec.rb
```

**Step 8: Update GENERATOR_MAP**

In `lib/lowmu/commands/generate.rb`, replace `"substack" => Generators::Substack` with:

```ruby
"substack_newsletter" => Generators::SubstackNewsletter,
"substack_note"       => Generators::SubstackNote,
```

**Step 9: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing

**Step 10: Commit**

```bash
git add -u lib/ spec/
git commit -m "feat: replace Substack with SubstackNewsletter (long) and SubstackNote (short)"
```

---

### Task 9: Generators::Mastodon — FORM constant, content_type-driven prompts

Remove internal front-matter type detection; use `@content_type` set by Base.

**Files:**
- Modify: `lib/lowmu/generators/mastodon.rb`
- Modify: `spec/lowmu/generators/mastodon_spec.rb`

**Step 1: Update the spec**

The spec already passes content_type via the generator helper (updated in Task 6). Verify context names match — update the `context` strings to reference `content_type :post` and `content_type :note` instead of `type: post/note`. Also add a FORM test:

In `spec/lowmu/generators/mastodon_spec.rb`, add before the `describe "#generate"` block:

```ruby
it "has FORM :short" do
  expect(described_class::FORM).to eq(:short)
end
```

**Step 2: Run to confirm FORM test fails**

```bash
bundle exec rspec spec/lowmu/generators/mastodon_spec.rb
```
Expected: 1 failure on `FORM`

**Step 3: Update the implementation**

Replace `lib/lowmu/generators/mastodon.rb`:

```ruby
module Lowmu
  module Generators
    class Mastodon < Base
      FORM = :short
      OUTPUT_FILE = "mastodon.txt"
      MAX_CHARS = 500

      POST_PROMPT = <<~PROMPT
        Write a Mastodon post announcing the following blog post. Requirements:
        - Must be under %d characters total (including the [URL] placeholder)
        - Capture the key insight or hook from the post
        - Use a conversational, authentic tone — not marketing speak
        - Include 2-3 relevant hashtags at the end
        - End with [URL] as a placeholder for the post URL

        Blog post:
        %s

        Return only the Mastodon post text.
      PROMPT

      NOTE_PROMPT = <<~PROMPT
        Condense the following note for Mastodon. Requirements:
        - Must be under %d characters total
        - Preserve the key point of the note
        - Maintain the author's voice and tone
        - Include 2-3 relevant hashtags at the end

        Note:
        %s

        Return only the Mastodon post text.
      PROMPT

      def generate
        content = if @content_type == :note
          loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
          parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
          body = parsed.content.strip
          body.length <= MAX_CHARS ? body : ask_llm(NOTE_PROMPT % [MAX_CHARS, body])
        else
          ask_llm(POST_PROMPT % [MAX_CHARS, original_content])
        end

        if content.length > MAX_CHARS
          content += "\n\n<!-- lowmu: content is #{content.length} chars, target is #{MAX_CHARS} chars. Please shorten before publishing. -->"
        end

        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 4: Run spec**

```bash
bundle exec rspec spec/lowmu/generators/mastodon_spec.rb
```
Expected: all pass

**Step 5: Commit**

```bash
git add lib/lowmu/generators/mastodon.rb spec/lowmu/generators/mastodon_spec.rb
git commit -m "feat: Mastodon generator declares FORM :short, uses content_type from pipeline"
```

---

### Task 10: Add Generators::LinkedinPost and LinkedinArticle (replace Linkedin)

**Files:**
- Create: `lib/lowmu/generators/linkedin_post.rb`
- Create: `lib/lowmu/generators/linkedin_article.rb`
- Create: `spec/lowmu/generators/linkedin_post_spec.rb`
- Create: `spec/lowmu/generators/linkedin_article_spec.rb`
- Delete: `lib/lowmu/generators/linkedin.rb`
- Delete: `spec/lowmu/generators/linkedin_spec.rb`
- Modify: `lib/lowmu/commands/generate.rb` (update GENERATOR_MAP)

**Step 1: Write LinkedinPost spec**

Create `spec/lowmu/generators/linkedin_post_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinPost do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_post_test") }
  let(:target_config) { {"name" => "linkedin-post", "type" => "linkedin_post"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with content_type :post" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Professional hook.\n\nKey insight.\n\nRead more: [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :post).generate).to eq("linkedin_post.md")
      end

      it "creates linkedin_post.md" do
        generator(source_path, :post).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_post.md"))).to be true
      end

      it "sends a prompt mentioning LinkedIn" do
        mock_chat = mock_llm_response(content: "LinkedIn post")
        generator(source_path, :post).generate
        expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
      end
    end

    context "with content_type :note" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      before { mock_llm_response(content: "Quick insight on LinkedIn.") }

      it "returns the output filename" do
        expect(generator(source_path, :note).generate).to eq("linkedin_post.md")
      end

      it "creates linkedin_post.md" do
        generator(source_path, :note).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_post.md"))).to be true
      end
    end
  end
end
```

**Step 2: Write LinkedinArticle spec**

Create `spec/lowmu/generators/linkedin_article_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinArticle do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_article_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "linkedin-article", "type" => "linkedin_article"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :post, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    before { mock_llm_response(content: "# Article Headline\n\nExpanded article content.") }

    it "returns the output filename" do
      expect(generator.generate).to eq("linkedin_article.md")
    end

    it "creates linkedin_article.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "linkedin_article.md"))).to be true
    end

    it "sends post content to LLM" do
      mock_chat = mock_llm_response(content: "article output")
      generator.generate
      expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
    end
  end
end
```

**Step 3: Run to confirm failures**

```bash
bundle exec rspec spec/lowmu/generators/linkedin_post_spec.rb spec/lowmu/generators/linkedin_article_spec.rb
```
Expected: fail with `uninitialized constant`

**Step 4: Implement LinkedinPost**

Create `lib/lowmu/generators/linkedin_post.rb`:

```ruby
module Lowmu
  module Generators
    class LinkedinPost < Base
      FORM = :short
      OUTPUT_FILE = "linkedin_post.md"

      POST_PROMPT = <<~PROMPT
        Write a LinkedIn post based on the following blog post. Requirements:
        - Professional but conversational tone
        - Lead with a strong hook (the first line is critical on LinkedIn)
        - Summarize key insights in 3-5 short paragraphs or bullet points
        - End with "Read the full post: [URL]"
        - Between 150-300 words total

        Blog post:
        %s

        Return only the LinkedIn post text.
      PROMPT

      NOTE_PROMPT = <<~PROMPT
        Write a LinkedIn post based on the following short note. Requirements:
        - Professional but conversational tone
        - Lead with the key insight
        - Keep it concise, 1-2 short paragraphs
        - 50-150 words total

        Note:
        %s

        Return only the LinkedIn post text.
      PROMPT

      def generate
        prompt = @content_type == :note ? NOTE_PROMPT : POST_PROMPT
        content = ask_llm(prompt % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 5: Implement LinkedinArticle**

Create `lib/lowmu/generators/linkedin_article.rb`:

```ruby
module Lowmu
  module Generators
    class LinkedinArticle < Base
      FORM = :long
      OUTPUT_FILE = "linkedin_article.md"

      PROMPT = <<~PROMPT
        Write a long-form LinkedIn article based on the following blog post. Requirements:
        - Professional tone with personal insights
        - Include a compelling headline
        - Expand on the key ideas with LinkedIn-appropriate formatting
        - 500-1000 words
        - End with a call to action

        Blog post:
        %s

        Return only the article content with headline.
      PROMPT

      def generate
        content = ask_llm(PROMPT % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 6: Run new specs**

```bash
bundle exec rspec spec/lowmu/generators/linkedin_post_spec.rb spec/lowmu/generators/linkedin_article_spec.rb
```
Expected: all pass

**Step 7: Delete old Linkedin files**

```bash
rm lib/lowmu/generators/linkedin.rb spec/lowmu/generators/linkedin_spec.rb
```

**Step 8: Update GENERATOR_MAP**

In `lib/lowmu/commands/generate.rb`, replace `"linkedin" => Generators::Linkedin` with:

```ruby
"linkedin_post"    => Generators::LinkedinPost,
"linkedin_article" => Generators::LinkedinArticle,
```

The final GENERATOR_MAP should be:

```ruby
GENERATOR_MAP = {
  "substack_newsletter" => Generators::SubstackNewsletter,
  "substack_note"       => Generators::SubstackNote,
  "mastodon"            => Generators::Mastodon,
  "linkedin_post"       => Generators::LinkedinPost,
  "linkedin_article"    => Generators::LinkedinArticle
}.freeze
```

**Step 9: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing

**Step 10: Commit**

```bash
git add -u lib/ spec/
git commit -m "feat: replace Linkedin with LinkedinPost (short) and LinkedinArticle (long)"
```

---

### Task 11: Commands::Generate — compound key and form-factor filtering

**Files:**
- Modify: `lib/lowmu/commands/generate.rb`
- Modify: `spec/lowmu/commands/generate_spec.rb`

**Step 1: Update the spec**

Replace `spec/lowmu/commands/generate_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Commands::Generate do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo_content") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:post_dir) { File.join(hugo_content_dir, "posts", "my-post") }
  let(:note_dir) { File.join(hugo_content_dir, "notes") }
  let(:source_path) { File.join(post_dir, "index.md") }
  let(:note_source_path) { File.join(note_dir, "my-note.md") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }

  let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon"} }
  let(:newsletter_target) { {"name" => "substack-newsletter", "type" => "substack_newsletter"} }
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
    allow(config).to receive(:target_config).with("substack-newsletter").and_return(newsletter_target)
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  def mark_generated(key)
    store.ensure_slug_dir(key)
    output = File.join(store.slug_dir(key), "mastodon.txt")
    File.write(output, "generated content")
    past = Time.now - 60
    File.utime(past, past, source_path)
  end

  def mark_stale(key)
    store.ensure_slug_dir(key)
    output = File.join(store.slug_dir(key), "mastodon.txt")
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
        expect(results.map { |r| r[:target] }).to contain_exactly("mastodon", "substack-newsletter")
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
        expect(note_results.map { |r| r[:target] }).not_to include("substack-newsletter")
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
end
```

**Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb
```
Expected: failures (compound key not used, form filtering missing)

**Step 3: Rewrite the implementation**

Replace `lib/lowmu/commands/generate.rb`:

```ruby
module Lowmu
  module Commands
    class Generate
      GENERATOR_MAP = {
        "substack_newsletter" => Generators::SubstackNewsletter,
        "substack_note"       => Generators::SubstackNote,
        "mastodon"            => Generators::Mastodon,
        "linkedin_post"       => Generators::LinkedinPost,
        "linkedin_article"    => Generators::LinkedinArticle
      }.freeze

      def initialize(key_filter = nil, config:, target: nil, force: false)
        @key_filter = key_filter
        @target_filter = target
        @force = force
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        configure_llm
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter
        warn_stale(items)
        items.select { |item| should_generate?(item) }
          .flat_map { |item| generate_item(item) }
      end

      private

      def should_generate?(item)
        status = item_status(item)
        return false if status == :ignore
        return true if @force
        if @key_filter
          status == :pending || status == :stale
        else
          status == :pending
        end
      end

      def warn_stale(items)
        items.each do |item|
          next unless item_status(item) == :stale
          next if should_generate?(item)
          warn "Warning: '#{item[:key]}' is stale. Run `lowmu generate #{item[:key]}` to regenerate."
        end
      end

      def item_status(item)
        @status_cache ||= {}
        @status_cache[item[:key]] ||= SlugStatus.new(item[:key], item[:source_path], @store).call
      end

      def generate_item(item)
        @store.ensure_slug_dir(item[:key])

        applicable_targets(item[:content_type]).map do |target_name|
          target_config = @config.target_config(target_name)
          generator_class = generator_class_for(target_name)

          output_file = generator_class.new(
            @store.slug_dir(item[:key]),
            item[:source_path],
            item[:content_type],
            target_config,
            @config.llm
          ).generate

          {key: item[:key], target: target_name, file: output_file}
        end
      end

      def applicable_targets(content_type)
        resolve_targets.reject do |target_name|
          content_type == :note && generator_class_for(target_name)::FORM == :long
        end
      end

      def generator_class_for(target_name)
        target_config = @config.target_config(target_name)
        GENERATOR_MAP.fetch(target_config["type"]) do
          raise Error, "Unknown target type: #{target_config["type"]}"
        end
      end

      def resolve_targets
        if @target_filter
          unless @config.targets.any? { |t| t["name"] == @target_filter }
            raise Error, "Unknown target: #{@target_filter}"
          end
          [@target_filter]
        else
          @config.targets.map { |t| t["name"] }
        end
      end

      def configure_llm
        RubyLLM.configure do |c|
          c.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
        end
      end
    end
  end
end
```

**Step 4: Run spec**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb
```
Expected: all pass

**Step 5: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing except cli_spec (next task)

**Step 6: Commit**

```bash
git add lib/lowmu/commands/generate.rb spec/lowmu/commands/generate_spec.rb
git commit -m "feat: Generate command uses compound key and filters long-form targets for notes"
```

---

### Task 12: CLI — compound key in place of bare slug

**Files:**
- Modify: `lib/lowmu/cli.rb`
- Modify: `spec/lowmu/cli_spec.rb`

**Step 1: Update the spec**

In `spec/lowmu/cli_spec.rb`:

In the `#generate` context "when content is generated", update the stubbed return value to use `key:` instead of `slug:`:

```ruby
allow(command).to receive(:call).and_return([
  {key: "posts/my-post", target: "mastodon", file: "/tmp/lowmu/posts/my-post/mastodon.txt"},
  {key: "posts/my-post", target: "linkedin-post", file: "/tmp/lowmu/posts/my-post/linkedin_post.md"}
])
```

Update the expectation:

```ruby
it "reports each generated result" do
  expect { cli.generate }.to output(
    /Generated mastodon for posts\/my-post.*Generated linkedin-post for posts\/my-post/m
  ).to_stdout
end
```

In the `#status` context "when content exists", update the stubbed return value and expectation:

```ruby
allow(command).to receive(:call).and_return([
  {key: "posts/my-post", status: :pending},
  {key: "notes/other-note", status: :generated}
])
```

```ruby
it "prints each key with its status" do
  expect { cli.status }.to output(
    /posts\/my-post: pending.*notes\/other-note: generated/m
  ).to_stdout
end
```

**Step 2: Run to confirm failures**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb
```
Expected: failures on status and generate output format

**Step 3: Update the implementation**

In `lib/lowmu/cli.rb`:

Change the `status` method output line:
```ruby
results.each { |entry| say "#{entry[:key]}: #{entry[:status]}" }
```

Change the `generate` method output line:
```ruby
results.each { |r| say "Generated #{r[:target]} for #{r[:key]}: #{r[:file]}" }
```

**Step 4: Run spec**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb
```
Expected: all pass

**Step 5: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing

**Step 6: Commit**

```bash
git add lib/lowmu/cli.rb spec/lowmu/cli_spec.rb
git commit -m "feat: CLI displays compound key (section/slug) in status and generate output"
```

---

### Task 13: Update fixtures and README

**Files:**
- Modify: `spec/fixtures/sample_config.yml`
- Modify: `spec/lowmu/config_spec.rb`
- Modify: `README.md`

**Step 1: Update sample_config.yml**

Replace `spec/fixtures/sample_config.yml`:

```yaml
hugo_content_dir: /tmp/lowmu_test_hugo_content
content_dir: /tmp/lowmu_test_content

post_dirs: [posts]
note_dirs: [notes]

llm:
  provider: anthropic
  model: claude-opus-4-6

targets:
  - name: substack-newsletter
    type: substack_newsletter
  - name: substack-note
    type: substack_note
  - name: mastodon
    type: mastodon
    base_url: https://mastodon.social
  - name: linkedin-post
    type: linkedin_post
  - name: linkedin-article
    type: linkedin_article
```

**Step 2: Update config_spec target count**

In `spec/lowmu/config_spec.rb`, change:
```ruby
expect(config.targets.length).to eq(4)
```
to:
```ruby
expect(config.targets.length).to eq(5)
```

**Step 3: Update README example config**

In `README.md`, replace the `targets:` block in the Example config section:

```yaml
targets:
  - name: substack-newsletter
    type: substack_newsletter

  - name: substack-note
    type: substack_note

  - name: mastodon
    type: mastodon
    base_url: https://mastodon.social

  - name: linkedin-post
    type: linkedin_post

  - name: linkedin-article
    type: linkedin_article
```

Also update the `hugo_content_dir` example line and add the new keys:

```yaml
# Hugo content root (posts and notes live as subdirectories here)
hugo_content_dir: ~/projects/myblog/content

# Which subdirectories are long-form posts (default: [posts])
post_dirs: [posts]

# Which subdirectories are short-form notes (default: [notes])
note_dirs: [notes]
```

**Step 4: Run full suite**

```bash
bundle exec rspec
```
Expected: all passing

**Step 5: Run linter**

```bash
bundle exec standardrb
```
Fix any style issues with `bundle exec standardrb --fix`.

**Step 6: Commit**

```bash
git add spec/fixtures/sample_config.yml spec/lowmu/config_spec.rb README.md
git commit -m "docs: update fixtures and README for new target types and dir config"
```

---

## Summary

After all 13 tasks, the system:
- Scans only `post_dirs` + `note_dirs` (ignoring `portfolio/`, `about/`, etc.)
- Tags every scanned item with `content_type` (`:post` or `:note`) and compound `key` (`"posts/jojo"`)
- Uses the compound key everywhere: ContentStore paths, ignore.yml, CLI output, filter args
- Filters long-form targets (`FORM = :long`) when processing notes
- Has 5 generator types: `SubstackNewsletter` (long), `SubstackNote` (short), `Mastodon` (short), `LinkedinPost` (short), `LinkedinArticle` (long)
