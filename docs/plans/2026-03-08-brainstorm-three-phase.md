# Brainstorm Three-Phase Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current single-shot brainstorm flow with a three-phase
pipeline: cache RSS items to local markdown files, index them with a cheap LLM
to extract remix dimensions, then brainstorm from the indexed palette using
round-robin source selection.

**Architecture:** RSS items are fetched and saved verbatim to `rss/cache/` on
first sight. A cheap LLM (Haiku) extracts the five remix dimensions into
`rss/index/` JSON files. The brainstorm phase loads recent index entries,
selects up to N items per source, and builds the idea-generation prompt from
structured metadata instead of raw excerpts. File sources are unchanged and
continue to feed directly into the brainstorm phase.

**Tech Stack:** Ruby, RubyLLM, RSpec. No new gems. Existing `DurationParser`
for `--recent`. Existing `BrainstormState` for tracking cached item IDs.

---

## Background: current data flow

```
CLI → Commands::Brainstorm
        → BrainstormState (filter seen IDs)
        → Sources::* (fetch items → {id, title, excerpt, source_name})
        → RubyLLM (all items in one prompt)
        → IdeaWriter (write idea files with source titles in *_source fields)
        → BrainstormState (mark IDs seen)
```

After this plan the flow becomes:

```
CLI → Commands::Brainstorm
  Phase 1 – Cache (RSS only):
        → Sources::RssSource (fetch items → {id, title, body, url, source_name})
        → BrainstormState (skip already-cached IDs)
        → RssItemCache (write rss/cache/*.md)
        → BrainstormState (mark IDs cached with path)
  Phase 2 – Index (RSS only):
        → RssItemIndexer (read cache files lacking an index → call cheap LLM → write rss/index/*.json)
  Phase 3 – Brainstorm (RSS + file sources):
        → Load recent rss/index/*.json + file source items
        → Round-robin select per-source N items
        → RubyLLM (prompt uses index dimensions, not raw excerpts)
        → IdeaWriter (write idea files; *_source fields = cache file path or "fresh")
```

---

## File map

| Action | Path |
|--------|------|
| Modify | `lib/lowmu/sources/rss_source.rb` |
| Modify | `lib/lowmu/brainstorm_state.rb` |
| **Create** | `lib/lowmu/rss_item_cache.rb` |
| **Create** | `lib/lowmu/rss_item_indexer.rb` |
| Modify | `lib/lowmu/commands/brainstorm.rb` |
| Modify | `lib/lowmu/idea_writer.rb` |
| Modify | `lib/lowmu/cli.rb` |
| Modify | `lib/lowmu/config.rb` |
| Modify | `spec/lowmu/sources/rss_source_spec.rb` |
| Modify | `spec/lowmu/brainstorm_state_spec.rb` |
| **Create** | `spec/lowmu/rss_item_cache_spec.rb` |
| **Create** | `spec/lowmu/rss_item_indexer_spec.rb` |
| Modify | `spec/lowmu/commands/brainstorm_spec.rb` |
| Modify | `spec/lowmu/idea_writer_spec.rb` |
| Modify | `spec/lowmu/config_spec.rb` |
| Modify | `spec/lowmu/cli_spec.rb` |

---

## Task 1: Extend RssSource to return full body and URL

RSS items need their full content and canonical URL for caching. Currently `parse_item` discards everything after the 200-word excerpt. We keep `excerpt` as-is (file sources and future compatibility) and add `body` and `url`.

**Files:**
- Modify: `lib/lowmu/sources/rss_source.rb:23-29`
- Modify: `spec/lowmu/sources/rss_source_spec.rb`

**Step 1: Write the failing test**

In `spec/lowmu/sources/rss_source_spec.rb`, inside `describe "#items"`, add:

```ruby
it "includes body (full stripped HTML content)" do
  item = source.items.first
  expect(item).to have_key(:body)
  expect(item[:body]).to be_a(String)
end

it "includes url" do
  item = source.items.first
  expect(item).to have_key(:url)
  expect(item[:url]).to eq("https://example.com/first-post")
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/sources/rss_source_spec.rb -e "includes body" -e "includes url"
```

Expected: FAIL — `:body` and `:url` not in hash.

**Step 3: Implement**

In `lib/lowmu/sources/rss_source.rb`, update `parse_item`:

```ruby
def parse_item(item)
  id    = atom_item?(item) ? (item.id&.content || item.link&.href) : (item.guid&.content || item.link)
  title = atom_item?(item) ? item.title&.content : item.title
  url   = atom_item?(item) ? item.link&.href : item.link
  body  = atom_item?(item) ? (item.content&.content || item.summary&.content || "") : (item.description || "")
  body  = strip_html(body)
  excerpt = body.split.first(EXCERPT_WORDS).join(" ")
  {id: id, title: title, url: url, body: body, excerpt: excerpt, source_name: @name}
end
```

**Step 4: Run full rss_source spec**

```bash
bundle exec rspec spec/lowmu/sources/rss_source_spec.rb
```

Expected: all green.

**Step 5: Commit**

```bash
git add lib/lowmu/sources/rss_source.rb spec/lowmu/sources/rss_source_spec.rb
git commit -m "feat: add body and url to RssSource items"
```

---

## Task 2: Redesign BrainstormState for cache tracking

The current state schema uses `last_seen_ids` (an array). We replace it with `cached_items` (a hash mapping item ID → relative cache path). This lets the brainstorm command look up the cache path for any item without scanning the filesystem.

**State file before:**
```yaml
sources:
  example-blog:
    last_seen_ids:
      - "https://example.com/post-1"
```

**State file after:**
```yaml
sources:
  example-blog:
    cached_items:
      "https://example.com/post-1": "rss/cache/2026-03-08-example-blog-first-post.md"
```

**Files:**
- Modify: `lib/lowmu/brainstorm_state.rb` (full rewrite — API changes)
- Modify: `spec/lowmu/brainstorm_state_spec.rb` (full rewrite)

**Note:** The old `last_seen_ids` format is abandoned. On upgrade, previously cached items will be treated as new and re-fetched once. That is acceptable.

**Step 1: Write the new spec (replace existing content)**

```ruby
require "spec_helper"

RSpec.describe Lowmu::BrainstormState do
  let(:content_dir) { Dir.mktmpdir("lowmu_state_test") }
  let(:state) { described_class.new(content_dir) }

  after { FileUtils.rm_rf(content_dir) }

  describe "#cached?" do
    it "returns false for an unknown id" do
      expect(state.cached?("my-source", "abc123")).to be false
    end

    it "returns true after mark_cached" do
      state.mark_cached("my-source", "abc123", "rss/cache/2026-03-08-my-source-foo.md")
      expect(state.cached?("my-source", "abc123")).to be true
    end

    it "returns false for an id from a different source" do
      state.mark_cached("source-a", "abc123", "rss/cache/2026-03-08-source-a-foo.md")
      expect(state.cached?("source-b", "abc123")).to be false
    end
  end

  describe "#cache_path_for" do
    it "returns nil for an unknown id" do
      expect(state.cache_path_for("my-source", "abc123")).to be_nil
    end

    it "returns the path after mark_cached" do
      state.mark_cached("my-source", "abc123", "rss/cache/2026-03-08-my-source-foo.md")
      expect(state.cache_path_for("my-source", "abc123")).to eq("rss/cache/2026-03-08-my-source-foo.md")
    end
  end

  describe "#mark_cached" do
    it "persists to disk" do
      state.mark_cached("my-source", "abc123", "rss/cache/2026-03-08-my-source-foo.md")
      reloaded = described_class.new(content_dir)
      expect(reloaded.cached?("my-source", "abc123")).to be true
    end

    it "accumulates entries across calls" do
      state.mark_cached("my-source", "id1", "rss/cache/path1.md")
      state.mark_cached("my-source", "id2", "rss/cache/path2.md")
      expect(state.cached?("my-source", "id1")).to be true
      expect(state.cached?("my-source", "id2")).to be true
    end

    it "does not duplicate entries" do
      state.mark_cached("my-source", "id1", "rss/cache/path1.md")
      state.mark_cached("my-source", "id1", "rss/cache/path1.md")
      raw = YAML.safe_load_file(File.join(content_dir, "brainstorm_state.yml"))
      expect(raw["sources"]["my-source"]["cached_items"].count { |id, _| id == "id1" }).to eq(1)
    end
  end
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/brainstorm_state_spec.rb
```

Expected: many failures (wrong method names and schema).

**Step 3: Implement new BrainstormState**

Replace `lib/lowmu/brainstorm_state.rb`:

```ruby
module Lowmu
  class BrainstormState
    def initialize(content_dir)
      @path = File.join(File.expand_path(content_dir), "brainstorm_state.yml")
    end

    def cached?(source_name, id)
      source_items(source_name).key?(id)
    end

    def cache_path_for(source_name, id)
      source_items(source_name)[id]
    end

    def mark_cached(source_name, id, relative_path)
      data["sources"] ||= {}
      data["sources"][source_name] ||= {}
      data["sources"][source_name]["cached_items"] ||= {}
      data["sources"][source_name]["cached_items"][id] = relative_path
      File.write(@path, data.to_yaml)
    end

    private

    def source_items(source_name)
      data.dig("sources", source_name, "cached_items") || {}
    end

    def data
      @data ||= if File.exist?(@path)
        YAML.safe_load_file(@path) || {}
      else
        {}
      end
    end
  end
end
```

**Step 4: Run spec**

```bash
bundle exec rspec spec/lowmu/brainstorm_state_spec.rb
```

Expected: all green.

**Step 5: Run full suite to catch breakage**

```bash
bundle exec rspec
```

`Commands::Brainstorm` spec will fail because it calls `mark_seen`. That is expected — it will be fixed in Task 5.

**Step 6: Commit**

```bash
git add lib/lowmu/brainstorm_state.rb spec/lowmu/brainstorm_state_spec.rb
git commit -m "refactor: redesign BrainstormState to track cache paths per item"
```

---

## Task 3: Add `index_model` to Config

The indexing phase uses a cheaper LLM. Config gains an `index_model` reader that falls back to `model` if not set.

**Files:**
- Modify: `lib/lowmu/config.rb`
- Modify: `spec/lowmu/config_spec.rb`

**Step 1: Write the failing test**

In `spec/lowmu/config_spec.rb`, add a `describe "#index_model"` block:

```ruby
describe "#index_model" do
  it "returns the index_model from llm config when set" do
    config = described_class.new({
      "hugo_content_dir" => "/tmp/hugo",
      "targets" => ["mastodon_short"],
      "llm" => {"model" => "claude-opus-4-6", "index_model" => "claude-haiku-4-5-20251001"}
    })
    expect(config.index_model).to eq("claude-haiku-4-5-20251001")
  end

  it "falls back to model when index_model is not set" do
    config = described_class.new({
      "hugo_content_dir" => "/tmp/hugo",
      "targets" => ["mastodon_short"],
      "llm" => {"model" => "claude-opus-4-6"}
    })
    expect(config.index_model).to eq("claude-opus-4-6")
  end
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/config_spec.rb -e "index_model"
```

Expected: FAIL — undefined method.

**Step 3: Implement**

In `lib/lowmu/config.rb`, add `index_model` to the `attr_reader` line and initializer:

```ruby
attr_reader :hugo_content_dir, :content_dir, :llm, :targets, :post_dirs, :note_dirs, :persona, :sources, :index_model
```

In `initialize`:

```ruby
@index_model = @llm.fetch("index_model", @llm.fetch("model", nil))
```

**Step 4: Run spec**

```bash
bundle exec rspec spec/lowmu/config_spec.rb
```

Expected: all green.

**Step 5: Commit**

```bash
git add lib/lowmu/config.rb spec/lowmu/config_spec.rb
git commit -m "feat: add index_model to Config, falls back to model"
```

---

## Task 4: Create RssItemCache

Writes a single RSS item to `#{content_dir}/rss/cache/YYYY-MM-DD-#{source_slug}-#{title_slug}.md`. Returns the path relative to `content_dir` so it can be stored in state and referenced from idea files.

**Cache file format:**
```markdown
---
title: "Article Title"
url: "https://example.com/article"
source_name: example-blog
fetched_at: 2026-03-08
full_content: true
---

Full stripped text content here...
```

`full_content` is `true` when `body` is longer than `EXCERPT_WORDS` (200 words), indicating the feed provided the full article rather than just a summary.

**Files:**
- Create: `lib/lowmu/rss_item_cache.rb`
- Create: `spec/lowmu/rss_item_cache_spec.rb`

**Step 1: Write the spec**

```ruby
require "spec_helper"

RSpec.describe Lowmu::RssItemCache do
  let(:content_dir) { Dir.mktmpdir("lowmu_cache_test") }
  let(:cache) { described_class.new(content_dir) }
  let(:item) do
    {
      id: "https://example.com/post-1",
      title: "First Post About Ruby",
      url: "https://example.com/post-1",
      source_name: "example-blog",
      body: "Ruby is a great language. " * 50
    }
  end

  after { FileUtils.rm_rf(content_dir) }

  describe "#write" do
    it "returns a relative path starting with rss/cache/" do
      path = cache.write(item)
      expect(path).to start_with("rss/cache/")
    end

    it "returns a path ending in .md" do
      expect(cache.write(item)).to end_with(".md")
    end

    it "includes today's date in the filename" do
      expect(cache.write(item)).to include(Date.today.to_s)
    end

    it "creates the file on disk" do
      path = cache.write(item)
      expect(File.exist?(File.join(content_dir, path))).to be true
    end

    it "writes YAML front matter with title, url, source_name, fetched_at, full_content" do
      path = cache.write(item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("title: \"First Post About Ruby\"")
      expect(content).to include("url: https://example.com/post-1")
      expect(content).to include("source_name: example-blog")
      expect(content).to include("fetched_at: #{Date.today}")
    end

    it "marks full_content true when body exceeds 200 words" do
      path = cache.write(item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("full_content: true")
    end

    it "marks full_content false for a short body" do
      short_item = item.merge(body: "Just a short summary.")
      path = cache.write(short_item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("full_content: false")
    end

    it "writes the body after front matter" do
      path = cache.write(item)
      content = File.read(File.join(content_dir, path))
      expect(content).to include("Ruby is a great language.")
    end

    it "creates parent directories if they do not exist" do
      new_dir = File.join(Dir.mktmpdir, "new_content")
      described_class.new(new_dir).write(item)
      expect(Dir.exist?(File.join(new_dir, "rss", "cache"))).to be true
    end
  end
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/rss_item_cache_spec.rb
```

Expected: FAIL — `Lowmu::RssItemCache` uninitialized constant.

**Step 3: Implement**

Create `lib/lowmu/rss_item_cache.rb`:

```ruby
require "date"

module Lowmu
  class RssItemCache
    EXCERPT_WORDS = 200

    def initialize(content_dir)
      @content_dir = File.expand_path(content_dir)
      @cache_dir = File.join(@content_dir, "rss", "cache")
      FileUtils.mkdir_p(@cache_dir)
    end

    def write(item)
      relative_path = File.join("rss", "cache", filename_for(item))
      full_content = item[:body].split.length > EXCERPT_WORDS
      content = <<~MD
        ---
        title: #{item[:title].inspect}
        url: #{item[:url]}
        source_name: #{item[:source_name]}
        fetched_at: #{Date.today}
        full_content: #{full_content}
        ---

        #{item[:body]}
      MD
      File.write(File.join(@content_dir, relative_path), content)
      relative_path
    end

    private

    def filename_for(item)
      slug = item[:title].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      source_slug = item[:source_name].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      "#{Date.today}-#{source_slug}-#{slug}.md"
    end
  end
end
```

**Step 4: Add require to `lib/lowmu.rb`** (or wherever the project autoloads files — check the existing require pattern).

Run `grep -r "require.*brainstorm_state" lib/` to find where to add the new require.

**Step 5: Run spec**

```bash
bundle exec rspec spec/lowmu/rss_item_cache_spec.rb
```

Expected: all green.

**Step 6: Commit**

```bash
git add lib/lowmu/rss_item_cache.rb spec/lowmu/rss_item_cache_spec.rb
git commit -m "feat: add RssItemCache to write RSS items to local markdown files"
```

---

## Task 5: Create RssItemIndexer

Reads a cache file, calls the cheap LLM to extract the five remix dimensions, and writes a JSON index file to `rss/index/` with the same base name as the cache file.

**Index file format** (e.g., `rss/index/2026-03-08-example-blog-first-post.json`):
```json
{
  "title": "First Post About Ruby",
  "url": "https://example.com/post-1",
  "source_name": "example-blog",
  "fetched_at": "2026-03-08",
  "full_content": true,
  "cache_path": "rss/cache/2026-03-08-example-blog-first-post.md",
  "concept": "Ruby's metaprogramming enables DSLs",
  "angle": "Practical guide for intermediate developers",
  "audience": "Ruby developers who know the basics but want to go deeper",
  "examples": "Rails callbacks, method_missing, define_method",
  "conclusion": "Use sparingly; prefer explicit code in most cases"
}
```

**Files:**
- Create: `lib/lowmu/rss_item_indexer.rb`
- Create: `spec/lowmu/rss_item_indexer_spec.rb`

**Step 1: Write the spec**

```ruby
require "spec_helper"

RSpec.describe Lowmu::RssItemIndexer do
  let(:content_dir) { Dir.mktmpdir("lowmu_indexer_test") }
  let(:cache_relative_path) { "rss/cache/2026-03-08-example-blog-first-post.md" }
  let(:cache_full_path) { File.join(content_dir, cache_relative_path) }
  let(:index_relative_path) { "rss/index/2026-03-08-example-blog-first-post.json" }
  let(:llm_response) do
    <<~JSON
      {
        "concept": "Ruby metaprogramming for DSLs",
        "angle": "Practical guide",
        "audience": "Intermediate Ruby developers",
        "examples": "method_missing, define_method",
        "conclusion": "Use sparingly"
      }
    JSON
  end
  let(:indexer) { described_class.new(content_dir: content_dir, model: "claude-haiku-4-5-20251001") }

  before do
    FileUtils.mkdir_p(File.dirname(cache_full_path))
    File.write(cache_full_path, <<~MD)
      ---
      title: "First Post About Ruby"
      url: https://example.com/post-1
      source_name: example-blog
      fetched_at: 2026-03-08
      full_content: true
      ---

      Ruby is a great language for DSLs.
    MD
    mock_llm_response(content: llm_response)
    RubyLLM.configure { |c| c.anthropic_api_key = "test-key" }
  end

  after { FileUtils.rm_rf(content_dir) }

  describe "#index" do
    it "returns the relative index file path" do
      result = indexer.index(cache_relative_path)
      expect(result).to eq(index_relative_path)
    end

    it "creates the index file on disk" do
      indexer.index(cache_relative_path)
      expect(File.exist?(File.join(content_dir, index_relative_path))).to be true
    end

    it "writes valid JSON with all required fields" do
      indexer.index(cache_relative_path)
      data = JSON.parse(File.read(File.join(content_dir, index_relative_path)))
      expect(data["title"]).to eq("First Post About Ruby")
      expect(data["url"]).to eq("https://example.com/post-1")
      expect(data["source_name"]).to eq("example-blog")
      expect(data["cache_path"]).to eq(cache_relative_path)
      expect(data["concept"]).to eq("Ruby metaprogramming for DSLs")
      expect(data["angle"]).to eq("Practical guide")
      expect(data["audience"]).to eq("Intermediate Ruby developers")
      expect(data["examples"]).to eq("method_missing, define_method")
      expect(data["conclusion"]).to eq("Use sparingly")
    end

    it "skips LLM call and returns path if index file already exists" do
      indexer.index(cache_relative_path)
      # Reset mock to detect if LLM is called again
      mock_chat = mock_llm_response(content: llm_response)
      result = indexer.index(cache_relative_path)
      expect(mock_chat).not_to have_received(:ask)
      expect(result).to eq(index_relative_path)
    end

    context "with --rescan" do
      let(:indexer) { described_class.new(content_dir: content_dir, model: "claude-haiku-4-5-20251001", rescan: true) }

      it "re-runs the LLM even if index file exists" do
        indexer.index(cache_relative_path)
        mock_chat = mock_llm_response(content: llm_response)
        indexer.index(cache_relative_path)
        expect(mock_chat).to have_received(:ask)
      end
    end
  end
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/rss_item_indexer_spec.rb
```

Expected: FAIL — uninitialized constant.

**Step 3: Implement**

Create `lib/lowmu/rss_item_indexer.rb`:

```ruby
require "json"

module Lowmu
  class RssItemIndexer
    PROMPT = <<~PROMPT
      You are analyzing a single article to extract structured metadata for content remixing.
      Read the article below and return a JSON object with exactly these five keys:

        "concept"   – The core subject or topic being explored (one sentence).
        "angle"     – The stance or framing of the piece (one sentence: e.g. "A warning to...", "A beginner's guide to...", "A critique of...").
        "audience"  – Who the piece is written for and what they are assumed to know (one sentence).
        "examples"  – The specific tools, workflows, codebases, or scenarios used (one sentence).
        "conclusion" – What the reader is left thinking or encouraged to do (one sentence).

      Return ONLY the JSON object. No markdown, no commentary.

      <article>
      %{content}
      </article>
    PROMPT

    def initialize(content_dir:, model:, rescan: false)
      @content_dir = File.expand_path(content_dir)
      @index_dir = File.join(@content_dir, "rss", "index")
      @model = model
      @rescan = rescan
      FileUtils.mkdir_p(@index_dir)
    end

    def index(cache_relative_path)
      index_path = index_path_for(cache_relative_path)
      index_full_path = File.join(@content_dir, index_path)

      return index_path if File.exist?(index_full_path) && !@rescan

      cache_content = File.read(File.join(@content_dir, cache_relative_path))
      front_matter = parse_front_matter(cache_content)
      body = cache_content.split(/^---\s*$/, 3).last.to_s.strip

      prompt = PROMPT % {content: "#{front_matter["title"]}\n\n#{body}"}
      raw = RubyLLM.chat(model: @model).ask(prompt).content
      dimensions = JSON.parse(raw)

      data = front_matter.slice("title", "url", "source_name", "fetched_at", "full_content").merge(
        "cache_path" => cache_relative_path,
        "concept"    => dimensions["concept"],
        "angle"      => dimensions["angle"],
        "audience"   => dimensions["audience"],
        "examples"   => dimensions["examples"],
        "conclusion" => dimensions["conclusion"]
      )

      File.write(index_full_path, JSON.pretty_generate(data))
      index_path
    end

    private

    def index_path_for(cache_relative_path)
      basename = File.basename(cache_relative_path, ".md")
      File.join("rss", "index", "#{basename}.json")
    end

    def parse_front_matter(content)
      parts = content.split(/^---\s*$/, 3)
      return {} unless parts.length >= 3
      YAML.safe_load(parts[1]) || {}
    end
  end
end
```

**Step 4: Add require**

Add `require "lowmu/rss_item_indexer"` alongside the other requires in `lib/lowmu.rb` (or equivalent autoload location).

**Step 5: Run spec**

```bash
bundle exec rspec spec/lowmu/rss_item_indexer_spec.rb
```

Expected: all green.

**Step 6: Commit**

```bash
git add lib/lowmu/rss_item_indexer.rb spec/lowmu/rss_item_indexer_spec.rb
git commit -m "feat: add RssItemIndexer to extract remix dimensions from cached RSS items"
```

---

## Task 6: Restructure Commands::Brainstorm into three phases

This is the largest change. The command now orchestrates three phases. File
sources continue to work as before (fed directly into the brainstorm prompt).
The brainstorm prompt changes to use index metadata instead of raw excerpts.

The `--rescan` flag now means: re-cache all items (even if cached) AND re-index
all (even if indexed). The brainstorm phase selection (round-robin) is
unaffected by `--rescan`.

**New CLI options (wired up here, exposed in Task 7):**
- `--recent DURATION` (e.g., `7d`, `2w`) — only load index files fetched within this window; default: no filter (use all)
- `--per-source N` — items per source to include in the brainstorm prompt; default: 3

**Files:**
- Modify: `lib/lowmu/commands/brainstorm.rb` (full rewrite)
- Modify: `spec/lowmu/commands/brainstorm_spec.rb`

**Step 1: Update the spec**

The existing spec uses a file source. Keep the file-source tests but update the
assertion about state (from `mark_seen` → `mark_cached`). Add an RSS-specific
test for the cache/index phases.

Replace `spec/lowmu/commands/brainstorm_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Commands::Brainstorm do
  let(:hugo_content_dir) { Dir.mktmpdir("lowmu_hugo") }
  let(:content_dir)      { Dir.mktmpdir("lowmu_content") }
  let(:notes_file) do
    path = File.join(Dir.mktmpdir, "ideas.md")
    File.write(path, "## Ruby Testing Tips\nGreat ideas about testing.\n\n## Metaprogramming Patterns\nPatterns for Ruby metaprogramming.\n")
    path
  end
  let(:config) do
    instance_double(Lowmu::Config,
      content_dir: content_dir,
      llm: {"model" => "claude-opus-4-6"},
      index_model: "claude-opus-4-6",
      persona: "I write about software engineering.",
      sources: [{"type" => "file", "name" => "my-notes", "path" => notes_file}])
  end
  let(:llm_response) do
    <<~RESPONSE
      TITLE: Testing Ruby Applications
      CONCEPT_SOURCE: fresh
      ANGLE_SOURCE: fresh
      AUDIENCE_SOURCE: fresh
      EXAMPLES_SOURCE: fresh
      CONCLUSION_SOURCE: fresh
      BODY:
      A comprehensive look at testing strategies for Ruby.

      ---

      TITLE: Effective Metaprogramming
      CONCEPT_SOURCE: fresh
      ANGLE_SOURCE: fresh
      AUDIENCE_SOURCE: fresh
      EXAMPLES_SOURCE: fresh
      CONCLUSION_SOURCE: fresh
      BODY:
      How to use Ruby metaprogramming without losing your mind.
    RESPONSE
  end

  before do
    mock_llm_response(content: llm_response)
    RubyLLM.configure { |c| c.anthropic_api_key = "test-key" }
  end

  after do
    FileUtils.rm_rf([hugo_content_dir, content_dir])
  end

  describe "#call" do
    it "returns an array of generated filenames" do
      files = described_class.new(config: config, num: 2).call
      expect(files.length).to eq(2)
    end

    it "writes long-form idea files by default" do
      files = described_class.new(config: config, num: 2).call
      expect(files.first).to start_with("long-")
    end

    it "writes short-form idea files when form is short" do
      files = described_class.new(config: config, form: "short", num: 2).call
      expect(files.first).to start_with("short-")
    end

    it "writes files to $content_dir/ideas/" do
      files = described_class.new(config: config, num: 2).call
      ideas_dir = File.join(content_dir, "ideas")
      expect(File.exist?(File.join(ideas_dir, files.first))).to be true
    end

    it "includes persona in the LLM prompt" do
      mock_chat = mock_llm_response(content: llm_response)
      described_class.new(config: config, num: 2).call
      expect(mock_chat).to have_received(:ask).with(including("software engineering"))
    end

    context "with an RSS source" do
      let(:fixture_xml) { File.read("spec/fixtures/sample_feed.xml") }
      let(:rss_config) do
        instance_double(Lowmu::Config,
          content_dir: content_dir,
          llm: {"model" => "claude-opus-4-6"},
          index_model: "claude-opus-4-6",
          persona: "I write about software engineering.",
          sources: [{"type" => "rss", "name" => "example-blog", "url" => "https://example.com/feed.xml"}])
      end

      before do
        allow(URI).to receive(:open).and_return(StringIO.new(fixture_xml))
        # Second mock_llm_response call for indexer (index extraction)
        # Use allow on the chain so both indexing and brainstorm LLM calls work
      end

      it "creates cache files under rss/cache/" do
        described_class.new(config: rss_config, num: 1).call
        cache_dir = File.join(content_dir, "rss", "cache")
        expect(Dir.exist?(cache_dir)).to be true
        expect(Dir.glob("#{cache_dir}/*.md")).not_to be_empty
      end

      it "creates index files under rss/index/" do
        described_class.new(config: rss_config, num: 1).call
        index_dir = File.join(content_dir, "rss", "index")
        expect(Dir.exist?(index_dir)).to be true
        expect(Dir.glob("#{index_dir}/*.json")).not_to be_empty
      end

      it "does not re-cache items on a second run" do
        described_class.new(config: rss_config, num: 1).call
        expect(URI).to receive(:open).once # should not fetch again
        described_class.new(config: rss_config, num: 1).call
      end
    end

    it "raises an error when no source items are available" do
      empty_config = instance_double(Lowmu::Config,
        content_dir: content_dir,
        llm: {"model" => "claude-opus-4-6"},
        index_model: "claude-opus-4-6",
        persona: "...",
        sources: [{"type" => "file", "name" => "empty", "path" => Tempfile.new.path}])
      expect { described_class.new(config: empty_config, num: 2).call }
        .to raise_error(Lowmu::Error, /No source items/)
    end
  end
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/commands/brainstorm_spec.rb
```

Expected: failures due to old API.

**Step 3: Implement new Commands::Brainstorm**

Replace `lib/lowmu/commands/brainstorm.rb`:

```ruby
require "json"

module Lowmu
  module Commands
    class Brainstorm
      def initialize(config:, form: "long", num: 5, rescan: false, recent: nil, per_source: 3)
        @config = config
        @form = form
        @num = num
        @rescan = rescan
        @recent = recent
        @per_source = per_source
        @state = BrainstormState.new(config.content_dir)
        @writer = IdeaWriter.new(File.join(config.content_dir, "ideas"))
      end

      def call
        configure_llm
        cache_rss_items
        index_rss_items
        palette = build_palette
        raise Error, "No source items found. Add sources to your config or use --rescan." if palette.empty?

        response = ask_llm(build_prompt(palette))
        ideas = parse_response(response)
        @writer.write_all(ideas)
      end

      private

      # Phase 1: fetch and cache new RSS items
      def cache_rss_items
        rss_sources.each do |source|
          cache = RssItemCache.new(@config.content_dir)
          build_rss_source(source).items.each do |item|
            next if @state.cached?(@rescan ? nil : source["name"], item[:id]) && !@rescan
            path = cache.write(item)
            @state.mark_cached(source["name"], item[:id], path)
          end
        end
      end

      # Phase 2: index any cache files that lack a corresponding index file
      def index_rss_items
        indexer = RssItemIndexer.new(
          content_dir: @config.content_dir,
          model: @config.index_model,
          rescan: @rescan
        )
        cache_dir = File.join(@config.content_dir, "rss", "cache")
        return unless Dir.exist?(cache_dir)

        Dir.glob("#{cache_dir}/*.md").each do |full_path|
          relative = full_path.delete_prefix("#{File.expand_path(@config.content_dir)}/")
          indexer.index(relative)
        end
      end

      # Phase 3a: build the palette from index files + file sources
      def build_palette
        rss_items = load_index_items
        file_items = load_file_items
        (rss_items + file_items)
      end

      def load_index_items
        index_dir = File.join(@config.content_dir, "rss", "index")
        return [] unless Dir.exist?(index_dir)

        all = Dir.glob("#{index_dir}/*.json").filter_map do |path|
          JSON.parse(File.read(path))
        rescue JSON::ParserError
          nil
        end

        all = filter_by_recent(all) if @recent

        # Round-robin: up to @per_source items per source
        by_source = all.group_by { |item| item["source_name"] }
        by_source.flat_map { |_, items| items.first(@per_source) }
      end

      def filter_by_recent(items)
        cutoff = Date.today - (DurationParser.parse(@recent) / 86_400)
        items.select do |item|
          fetched = Date.parse(item["fetched_at"].to_s) rescue nil
          fetched && fetched >= cutoff
        end
      end

      def load_file_items
        file_sources.flat_map do |source|
          build_file_source(source).items
        end
      end

      def build_prompt(palette)
        items_text = palette.map { |item| format_palette_item(item) }.join("\n\n---\n\n")
        form_instruction = @form == "short" ?
          "Write each idea as a complete ~500 word draft." :
          "Write each idea as a one-paragraph summary followed by a list of potential sections."

        <<~PROMPT
          You are a creative content strategist specializing in AI-assisted software development.
          Your job is to generate original article ideas inspired by — but clearly distinct from —
          a set of source articles provided as structured metadata.

          You are NOT summarizing or restating these articles. You are remixing them.

          Each article idea you generate should borrow each of the following elements from a
          DIFFERENT source article:

          1. **The concept or topic**
          2. **The angle or take**
          3. **The audience and framing**
          4. **The examples or scenarios**
          5. **The conclusion or proposed solution**

          Here is the author persona:

              #{@config.persona}

          Here are recent articles from a curated feed, each pre-analyzed for remix dimensions:

          <articles>
              #{items_text}
          </articles>

          Generate #{@num} original article ideas for #{@form}-form posts.
          For each idea:

          - **Pitch:** #{form_instruction}
          - **Audience:** Who is this for and what do they already know?
          - **Format:** What structure will this take?
          - **Remix breakdown:** For each of the five elements, name which source article it came
            from (use the title) — or note it was invented fresh.

          Format your response for each idea exactly as follows:

            TITLE: A one-line title for the idea
            CONCEPT_SOURCE: Title of source article (or "fresh")
            ANGLE_SOURCE: Title of source article (or "fresh")
            AUDIENCE_SOURCE: Title of source article (or "fresh")
            EXAMPLES_SOURCE: Title of source article (or "fresh")
            CONCLUSION_SOURCE: Title of source article (or "fresh")
            BODY: A detailed description of the idea. Several paragraphs.

          Provide exactly #{@num} ideas, each separated by "---".
        PROMPT
      end

      def format_palette_item(item)
        if item.is_a?(Hash) && item.key?("concept")
          # Index item (RSS)
          "Title: #{item["title"]}\nSource: #{item["source_name"]}\n" \
            "Concept: #{item["concept"]}\nAngle: #{item["angle"]}\n" \
            "Audience: #{item["audience"]}\nExamples: #{item["examples"]}\n" \
            "Conclusion: #{item["conclusion"]}"
        else
          # File source item (legacy format)
          "Source: #{item[:source_name]}\nTitle: #{item[:title]}\n#{item[:excerpt]}"
        end
      end

      def parse_response(response)
        blocks = response.split(/^---$/).map(&:strip).reject(&:empty?)
        blocks.first(@num).filter_map do |block|
          title_match      = block.match(/^TITLE:\s*(.+)$/)
          concept_match    = block.match(/^CONCEPT_SOURCE:\s*(.+)$/)
          angle_match      = block.match(/^ANGLE_SOURCE:\s*(.+)$/)
          audience_match   = block.match(/^AUDIENCE_SOURCE:\s*(.+)$/)
          examples_match   = block.match(/^EXAMPLES_SOURCE:\s*(.+)$/)
          conclusion_match = block.match(/^CONCLUSION_SOURCE:\s*(.+)$/)
          body_match       = block.match(/^BODY:\s*\n(.*)/m)
          next unless title_match && body_match
          {
            title: title_match[1].strip,
            concept_source: concept_match&.[](1)&.strip || "unknown",
            angle_source: angle_match&.[](1)&.strip || "unknown",
            audience_source: audience_match&.[](1)&.strip || "unknown",
            examples_source: examples_match&.[](1)&.strip || "unknown",
            conclusion_source: conclusion_match&.[](1)&.strip || "unknown",
            form: @form,
            body: body_match[1].strip
          }
        end
      end

      def rss_sources
        @config.sources.select { |s| s["type"] == "rss" }
      end

      def file_sources
        @config.sources.select { |s| s["type"] == "file" }
      end

      def build_rss_source(source)
        Sources::RssSource.new(name: source["name"], url: source["url"])
      end

      def build_file_source(source)
        Sources::FileSource.new(name: source["name"], path: source["path"])
      end

      def ask_llm(prompt)
        model = @config.llm.fetch("model") do
          raise Error, "No model configured. Run `lowmu configure` to set up an LLM provider."
        end
        RubyLLM.chat(model: model).ask(prompt).content
      rescue RubyLLM::ConfigurationError
        raise Error, "ANTHROPIC_API_KEY is not set. Please set it in your environment before running lowmu."
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

**Step 4: Run the brainstorm spec**

```bash
bundle exec rspec spec/lowmu/commands/brainstorm_spec.rb
```

Fix any failures. The RSS-source tests may need the fixture feed's LLM mock to
return a valid JSON for the indexer AND a valid idea block for brainstorming —
check what `mock_llm_response` does in `spec/support/` and set up the mock to
return different responses for the two LLM calls if needed.

**Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green.

**Step 6: Commit**

```bash
git add lib/lowmu/commands/brainstorm.rb spec/lowmu/commands/brainstorm_spec.rb
git commit -m "refactor: restructure brainstorm into three-phase cache/index/brainstorm pipeline"
```

---

## Task 7: Update IdeaWriter — no functional change needed

The `*_source` fields in idea files currently hold article titles (strings from the LLM). The LLM response now says things like `CONCEPT_SOURCE: First Post About Ruby` — still a title string. The IdeaWriter itself is unchanged.

The idea files will still reference source titles in frontmatter. If we want to store cache file paths instead, that requires a lookup table (title → cache path) that adds complexity. **Defer this.** The goal of enabling the draft command to pull source content can be addressed later by adding a `source_cache_paths` frontmatter field once the brainstorm prompt explicitly asks the LLM to name the cache file paths.

No changes to `lib/lowmu/idea_writer.rb` or its spec at this stage.

---

## Task 8: Add --recent and --per-source to CLI

**Files:**
- Modify: `lib/lowmu/cli.rb:104-120`
- Modify: `spec/lowmu/cli_spec.rb`

**Step 1: Write failing tests**

In `spec/lowmu/cli_spec.rb`, find the brainstorm section and add:

```ruby
it "passes --recent to the brainstorm command" do
  expect(Lowmu::Commands::Brainstorm).to receive(:new)
    .with(hash_including(recent: "7d"))
    .and_return(double(call: []))
  run_cli("brainstorm", "--recent", "7d")
end

it "passes --per-source to the brainstorm command" do
  expect(Lowmu::Commands::Brainstorm).to receive(:new)
    .with(hash_including(per_source: 5))
    .and_return(double(call: []))
  run_cli("brainstorm", "--per-source", "5")
end
```

**Step 2: Run to verify failure**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb -e "recent" -e "per-source"
```

**Step 3: Implement**

In `lib/lowmu/cli.rb`, update the brainstorm command block:

```ruby
desc "brainstorm", "Generate content ideas from configured sources"
method_option :form,       type: :string,  default: "long", desc: "Idea form: long or short"
method_option :num,        type: :numeric, default: 5,      desc: "Number of ideas to generate"
method_option :rescan,     type: :boolean,                  desc: "Ignore state and reprocess all source items"
method_option :recent,     type: :string,                   desc: "Only use sources fetched within duration (e.g. 7d, 2w)"
method_option :per_source, type: :numeric, default: 3,      desc: "Items per source to include in brainstorm palette"
def brainstorm
  command = Commands::Brainstorm.new(
    config:     Config.load,
    form:       options[:form],
    num:        options[:num],
    rescan:     options[:rescan],
    recent:     options[:recent],
    per_source: options[:per_source]
  )
  files = with_spinner("Brainstorming...") { command.call }
  say "Generated #{files.count} idea#{"s" unless files.count == 1}:"
  files.each { |f| say "  #{f}" }
rescue Lowmu::Error => e
  error_exit(e.message)
end
```

**Step 4: Run spec and full suite**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb
bundle exec rspec
```

Expected: all green.

**Step 5: Commit**

```bash
git add lib/lowmu/cli.rb spec/lowmu/cli_spec.rb
git commit -m "feat: add --recent and --per-source options to brainstorm command"
```

---

## Done

Run the full suite one final time:

```bash
bundle exec rspec
```

All green. Manual smoke test: add an RSS source to your config and run:

```bash
lowmu brainstorm --num=3 --per-source=2
```

Verify:
- `rss/cache/` contains `.md` files with front matter
- `rss/index/` contains `.json` files with the five remix dimensions
- `ideas/` contains idea files with remix breakdown from index metadata
- Re-running does not re-fetch or re-index already-cached items
- `--recent 7d` limits palette to items fetched in the last 7 days
- `--rescan` re-fetches and re-indexes everything
