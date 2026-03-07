# Status Command Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the flat single-status-per-input `lowmu status` command with a per-target tabular view, rich filter flags, a safety guard on `lowmu generate`, and a simplified `targets:` config format — removing `ignore.yml` entirely.

**Architecture:** A shared `Generators.registry` method replaces the private `GENERATOR_MAP` in `Generate`. A new `InputStatus` class returns a `{type => status}` hash for each Hugo item across all configured targets. `Commands::Status` filters rows and renders an ASCII table; `Commands::Generate` gains a required-scope guard and `--recent` option.

**Tech Stack:** Ruby, Thor (CLI), RSpec (tests), StandardRB (style), Zeitwerk (autoloading). Run tests with `bundle exec rspec`. Run style checks with `bundle exec standardrb --fix`.

**Design doc:** `docs/plans/2026-03-07-status-command-design.md`

---

## Conventions & key facts

- **Keys** are `"long/slug"` or `"short/slug"` — content type prefix + slug.
- **Targets** are generator type name strings: `"substack_long"`, `"substack_short"`, `"mastodon_short"`, `"linkedin_short"`, `"linkedin_long"`.
- **Generator classes** all live in `Lowmu::Generators::` and have two class constants: `FORM` (`:long` or `:short`) and `OUTPUT_FILE` (e.g. `"mastodon_short.md"`).
- **Content type** `:short` inputs cannot use `:long` generators → `:not_applicable`.
- `bundle exec rspec` requires SimpleCov ≥ 90% coverage — don't leave dead code.
- Commit after every task using conventional commit format.
- After each task run: `bundle exec rspec && bundle exec standardrb`

---

## Task 1: Add `Generators.registry` and update `Generate` to use it

**Files:**
- Create: `lib/lowmu/generators.rb`
- Modify: `lib/lowmu/commands/generate.rb` (replace `GENERATOR_MAP`)
- Modify: `spec/lowmu/generators/base_spec.rb` (add registry test)

Zeitwerk loads `lib/lowmu/generators.rb` as the namespace file for the
`Lowmu::Generators` module. Define the registry as a lazy method (not a constant)
so subclass references are only evaluated on first call — after all autoloads are done.

**Step 1: Write the failing test**

Add to `spec/lowmu/generators/base_spec.rb`:

```ruby
RSpec.describe Lowmu::Generators do
  describe ".registry" do
    it "returns a hash with all expected type keys" do
      expect(described_class.registry.keys).to contain_exactly(
        "substack_long", "substack_short", "mastodon_short",
        "linkedin_short", "linkedin_long"
      )
    end

    it "maps each key to a class with FORM and OUTPUT_FILE" do
      described_class.registry.each_value do |klass|
        expect(klass).to respond_to(:const_get)
        expect(klass::FORM).to be_in([:long, :short])
        expect(klass::OUTPUT_FILE).to be_a(String)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/lowmu/generators/base_spec.rb -e "registry" --format documentation
```

Expected: FAIL — `undefined method 'registry' for Lowmu::Generators`

**Step 3: Create `lib/lowmu/generators.rb`**

```ruby
module Lowmu
  module Generators
    def self.registry
      @registry ||= {
        "substack_long" => SubstackLong,
        "substack_short" => SubstackShort,
        "mastodon_short" => MastodonShort,
        "linkedin_short" => LinkedinShort,
        "linkedin_long" => LinkedinLong
      }.freeze
    end
  end
end
```

**Step 4: Update `lib/lowmu/commands/generate.rb`**

Remove `GENERATOR_MAP` and update `generator_class_for` to use the registry:

```ruby
# Remove this block entirely:
GENERATOR_MAP = {
  "substack_long" => Generators::SubstackLong,
  ...
}.freeze

# Update generator_class_for:
def generator_class_for(target_name)
  target_config = @config.target_config(target_name)
  Generators.registry.fetch(target_config["type"]) do
    raise Error, "Unknown target type: #{target_config["type"]}"
  end
end
```

**Step 5: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

Expected: All pass. Fix any StandardRB issues.

**Step 6: Commit**

```bash
git add lib/lowmu/generators.rb lib/lowmu/commands/generate.rb spec/lowmu/generators/base_spec.rb
git commit -m "refactor: extract Generators.registry from Generate::GENERATOR_MAP"
```

---

## Task 2: Update `Config` to parse the simplified targets format

**Files:**
- Modify: `lib/lowmu/config.rb`
- Modify: `spec/fixtures/sample_config.yml`
- Modify: `spec/lowmu/config_spec.rb`

New format: `targets:` is a flat list of generator type name strings (validated against
`Generators.registry`). `target_config(name)` is removed. `Config#targets` now returns
`Array<String>` of type names.

**Step 1: Update the fixture first**

Replace `spec/fixtures/sample_config.yml` contents:

```yaml
hugo_content_dir: /tmp/lowmu_test_hugo_content
content_dir: /tmp/lowmu_test_content

post_dirs: [posts]
note_dirs: [notes]

llm:
  provider: anthropic
  model: claude-opus-4-6

targets:
  - linkedin_long
  - linkedin_short
  - mastodon_short
  - substack_long
  - substack_short
```

**Step 2: Write failing tests**

Replace the `describe "#targets"` and `describe "#target_config"` and `describe "validation"` blocks in `spec/lowmu/config_spec.rb`:

```ruby
describe "#targets" do
  it "returns an array of type name strings" do
    config = described_class.load(fixture_path)
    expect(config.targets).to contain_exactly(
      "linkedin_long", "linkedin_short", "mastodon_short",
      "substack_long", "substack_short"
    )
  end
end

describe "validation" do
  it "raises when hugo_content_dir is missing" do
    expect { described_class.new({}) }
      .to raise_error(Lowmu::Error, /hugo_content_dir/)
  end

  it "does not raise when content_dir is missing (uses default)" do
    expect { described_class.new({"hugo_content_dir" => "/tmp/hugo"}) }.not_to raise_error
  end

  it "raises when a target type is not in the registry" do
    data = {"hugo_content_dir" => "/tmp", "targets" => ["unknown_type"]}
    expect { described_class.new(data) }
      .to raise_error(Lowmu::Error, /Unknown target type: unknown_type/)
  end

  it "raises when targets list is empty" do
    data = {"hugo_content_dir" => "/tmp", "targets" => []}
    expect { described_class.new(data) }
      .to raise_error(Lowmu::Error, /targets/)
  end
end
```

Remove the old `describe "#target_config"` block entirely.

**Step 3: Run tests to see failures**

```bash
bundle exec rspec spec/lowmu/config_spec.rb --format documentation
```

Expected: Several failures around targets parsing and removed `target_config`.

**Step 4: Rewrite `lib/lowmu/config.rb`**

```ruby
module Lowmu
  class Config
    DEFAULT_PATH = "~/.config/lowmu/config.yml"

    attr_reader :hugo_content_dir, :content_dir, :llm, :targets, :post_dirs, :note_dirs

    def self.load(path = DEFAULT_PATH)
      expanded = File.expand_path(path)
      unless File.exist?(expanded)
        raise Error, "Config file not found at #{expanded}. Run `lowmu configure` to create one."
      end
      data = YAML.safe_load_file(expanded) || {}
      new(data)
    end

    def initialize(data)
      @hugo_content_dir = File.expand_path(fetch!(data, "hugo_content_dir"))
      @content_dir = File.expand_path(data.fetch("content_dir", ".lowmu"))
      @llm = data.fetch("llm", {})
      @targets = parse_targets(data.fetch("targets", []))
      @post_dirs = data.fetch("post_dirs", ["posts"])
      @note_dirs = data.fetch("note_dirs", ["notes"])
    end

    private

    def fetch!(data, key)
      data.fetch(key) { raise Error, "Config missing required key: #{key}" }
    end

    def parse_targets(targets)
      raise Error, "Config must list at least one target under 'targets:'" if targets.empty?
      targets.each do |type|
        unless Generators.registry.key?(type.to_s)
          raise Error, "Unknown target type: #{type}. Valid types: #{Generators.registry.keys.join(", ")}"
        end
      end
      targets.map(&:to_s)
    end
  end
end
```

**Step 5: Fix `Commands::Generate` to work with new config format**

`Config#targets` now returns strings, not hashes. Update `resolve_targets` and
`applicable_targets` in `lib/lowmu/commands/generate.rb`:

```ruby
def applicable_targets(content_type)
  resolve_targets.reject do |type|
    content_type == :short && Generators.registry[type]::FORM == :long
  end
end

def generator_class_for(type)
  Generators.registry.fetch(type) do
    raise Error, "Unknown target type: #{type}"
  end
end

def resolve_targets
  if @target_filter
    unless @config.targets.include?(@target_filter)
      raise Error, "Unknown target: #{@target_filter}"
    end
    [@target_filter]
  else
    @config.targets
  end
end

def plan_item(item)
  @store.ensure_slug_dir(item[:key])
  applicable_targets(item[:content_type]).map do |type|
    generator_class = generator_class_for(type)
    generator = generator_class.new(
      @store.slug_dir(item[:key]),
      item[:source_path],
      item[:content_type],
      {},
      @config.llm
    )
    {key: item[:key], target: type, generator: generator}
  end
end
```

Note: `target_config` is gone — generator is now initialized with `{}` as the target config
(generators don't currently use it; this can be extended later).

**Step 6: Update `spec/lowmu/commands/generate_spec.rb`**

Update the config double and target references to use type strings:

```ruby
let(:config) do
  instance_double(Lowmu::Config,
    hugo_content_dir: hugo_content_dir,
    content_dir: content_dir,
    post_dirs: ["posts"],
    note_dirs: ["notes"],
    llm: llm_config,
    targets: ["mastodon_short", "substack_long"])
end

# Remove:
#   let(:mastodon_target) { ... }
#   let(:newsletter_target) { ... }
#   allow(config).to receive(:target_config)...

# Update result assertions from target names to type strings:
# "mastodon" → "mastodon_short"
# "substack-long" → "substack_long"
```

Also remove the `mark_ignored` helper and the "with an ignored post" context block
(ignore.yml is gone — that's tested elsewhere when ContentStore is updated).

**Step 7: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

Expected: All pass.

**Step 8: Commit**

```bash
git add lib/lowmu/config.rb lib/lowmu/commands/generate.rb \
        spec/fixtures/sample_config.yml spec/lowmu/config_spec.rb \
        spec/lowmu/commands/generate_spec.rb
git commit -m "refactor: simplify config targets to type-name strings, validate against registry"
```

---

## Task 3: Remove `ignore_slugs` from `ContentStore`

**Files:**
- Modify: `lib/lowmu/content_store.rb`
- Modify: `spec/lowmu/content_store_spec.rb`

**Step 1: Update spec — remove ignore tests, keep others**

Remove the `describe "#ignore_slugs"` block from `spec/lowmu/content_store_spec.rb`.
Also remove any reference to `IGNORE_FILE`.

**Step 2: Run spec to confirm it passes as-is (existing ones)**

```bash
bundle exec rspec spec/lowmu/content_store_spec.rb --format documentation
```

Expected: All existing tests pass (the ignore tests we just removed are gone).

**Step 3: Update `lib/lowmu/content_store.rb`**

Remove `IGNORE_FILE` constant and `ignore_slugs` method:

```ruby
module Lowmu
  class ContentStore
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

**Step 4: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

Expected: All pass.

**Step 5: Commit**

```bash
git add lib/lowmu/content_store.rb spec/lowmu/content_store_spec.rb
git commit -m "refactor: remove ignore_slugs and IGNORE_FILE from ContentStore"
```

---

## Task 4: Add `DurationParser`

**Files:**
- Create: `lib/lowmu/duration_parser.rb`
- Create: `spec/lowmu/duration_parser_spec.rb`

Parses strings like `"1w"`, `"3d"`, `"14d"` into seconds. Raises `Lowmu::Error` for
invalid input. Supported units: `d` (days) and `w` (weeks).

**Step 1: Write the failing spec**

```ruby
# spec/lowmu/duration_parser_spec.rb
require "spec_helper"

RSpec.describe Lowmu::DurationParser do
  describe ".parse" do
    it "parses days" do
      expect(described_class.parse("3d")).to eq(3 * 86_400)
    end

    it "parses weeks" do
      expect(described_class.parse("1w")).to eq(7 * 86_400)
    end

    it "parses multi-digit values" do
      expect(described_class.parse("14d")).to eq(14 * 86_400)
    end

    it "raises for an unknown unit" do
      expect { described_class.parse("2m") }
        .to raise_error(Lowmu::Error, /Invalid duration/)
    end

    it "raises for a non-numeric value" do
      expect { described_class.parse("banana") }
        .to raise_error(Lowmu::Error, /Invalid duration/)
    end

    it "raises for empty string" do
      expect { described_class.parse("") }
        .to raise_error(Lowmu::Error, /Invalid duration/)
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/lowmu/duration_parser_spec.rb --format documentation
```

Expected: FAIL — `uninitialized constant Lowmu::DurationParser`

**Step 3: Create `lib/lowmu/duration_parser.rb`**

```ruby
module Lowmu
  class DurationParser
    UNITS = {"d" => 86_400, "w" => 7 * 86_400}.freeze

    def self.parse(str)
      match = str.to_s.match(/\A(\d+)([dw])\z/)
      unless match
        raise Error, "Invalid duration #{str.inspect}. Use a number followed by d (days) or w (weeks), e.g. 3d, 1w."
      end
      match[1].to_i * UNITS[match[2]]
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/lowmu/duration_parser_spec.rb --format documentation
```

Expected: All pass.

**Step 5: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

**Step 6: Commit**

```bash
git add lib/lowmu/duration_parser.rb spec/lowmu/duration_parser_spec.rb
git commit -m "feat: add DurationParser for --recent flag (1w, 3d, etc.)"
```

---

## Task 5: Add `InputStatus` (replaces `SlugStatus`)

**Files:**
- Create: `lib/lowmu/input_status.rb`
- Create: `spec/lowmu/input_status_spec.rb`

`InputStatus#call` returns `{type_string => status_symbol}` for each enabled target.
`InputStatus#aggregate` returns the row-level summary.

Status rules per target:
- `:not_applicable` — content is `:short` and generator `FORM` is `:long`
- `:pending` — output file does not exist
- `:stale` — output exists but `mtime(source) > mtime(output)`
- `:done` — output exists and `mtime(source) <= mtime(output)`

Aggregate rules (ignoring `:not_applicable`):
- `:pending` — all applicable targets are `:pending`
- `:stale` — at least one applicable target is `:stale`
- `:done` — all applicable targets are `:done`
- `:partial` — some done, some pending (no stale)

**Step 1: Write the failing spec**

```ruby
# spec/lowmu/input_status_spec.rb
require "spec_helper"

RSpec.describe Lowmu::InputStatus do
  let(:hugo_content_dir) { Dir.mktmpdir("hugo") }
  let(:content_dir) { Dir.mktmpdir("lowmu") }
  let(:store) { Lowmu::ContentStore.new(content_dir) }
  let(:source_path) do
    path = File.join(hugo_content_dir, "post.md")
    File.write(path, "---\ntitle: Test\n---\nBody.")
    path
  end

  let(:long_item) { {key: "long/my-post", source_path: source_path, content_type: :long} }
  let(:short_item) { {key: "short/my-note", source_path: source_path, content_type: :short} }

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
  end

  def write_output(key, filename, mtime: nil)
    store.ensure_slug_dir(key)
    path = File.join(store.slug_dir(key), filename)
    File.write(path, "generated")
    File.utime(mtime, mtime, path) if mtime
    path
  end

  describe "#call" do
    context "with a long item and two enabled targets" do
      subject(:status) { described_class.new(long_item, ["mastodon_short", "substack_long"], store) }

      it "returns :pending for both when no output exists" do
        result = status.call
        expect(result).to eq("mastodon_short" => :pending, "substack_long" => :pending)
      end

      it "returns :done when output is newer than source" do
        past = Time.now - 120
        File.utime(past, past, source_path)
        write_output("long/my-post", "mastodon_short.md")
        write_output("long/my-post", "substack_long.md")
        result = status.call
        expect(result).to eq("mastodon_short" => :done, "substack_long" => :done)
      end

      it "returns :stale when source is newer than output" do
        past = Time.now - 120
        write_output("long/my-post", "mastodon_short.md", mtime: past)
        result = status.call
        expect(result["mastodon_short"]).to eq(:stale)
      end
    end

    context "with a short item and a long target enabled" do
      subject(:status) { described_class.new(short_item, ["substack_long", "mastodon_short"], store) }

      it "returns :not_applicable for the long target" do
        result = status.call
        expect(result["substack_long"]).to eq(:not_applicable)
      end

      it "returns :pending for the short target" do
        result = status.call
        expect(result["mastodon_short"]).to eq(:pending)
      end
    end
  end

  describe "#aggregate" do
    subject(:status) { described_class.new(long_item, ["mastodon_short", "substack_long"], store) }

    it "returns :pending when no output exists" do
      expect(status.aggregate).to eq(:pending)
    end

    it "returns :done when all applicable outputs are done" do
      past = Time.now - 120
      File.utime(past, past, source_path)
      write_output("long/my-post", "mastodon_short.md")
      write_output("long/my-post", "substack_long.md")
      expect(status.aggregate).to eq(:done)
    end

    it "returns :partial when some but not all outputs are done" do
      past = Time.now - 120
      File.utime(past, past, source_path)
      write_output("long/my-post", "mastodon_short.md")
      expect(status.aggregate).to eq(:partial)
    end

    it "returns :stale when any output is stale" do
      past = Time.now - 120
      write_output("long/my-post", "mastodon_short.md", mtime: past)
      expect(status.aggregate).to eq(:stale)
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```bash
bundle exec rspec spec/lowmu/input_status_spec.rb --format documentation
```

Expected: FAIL — `uninitialized constant Lowmu::InputStatus`

**Step 3: Create `lib/lowmu/input_status.rb`**

```ruby
module Lowmu
  class InputStatus
    def initialize(item, enabled_targets, content_store)
      @key = item[:key]
      @source_path = item[:source_path]
      @content_type = item[:content_type]
      @enabled_targets = enabled_targets
      @content_store = content_store
    end

    def call
      @result ||= @enabled_targets.each_with_object({}) do |type, hash|
        generator_class = Generators.registry[type]
        hash[type] = target_status(generator_class)
      end
    end

    def aggregate
      applicable = call.reject { |_, s| s == :not_applicable }.values
      return :pending if applicable.none? { |s| s == :done || s == :stale }
      return :stale if applicable.any? { |s| s == :stale }
      return :done if applicable.all? { |s| s == :done }
      :partial
    end

    private

    def target_status(generator_class)
      return :not_applicable if @content_type == :short && generator_class::FORM == :long

      output_path = File.join(@content_store.slug_dir(@key), generator_class::OUTPUT_FILE)
      return :pending unless File.exist?(output_path)

      File.mtime(@source_path) > File.mtime(output_path) ? :stale : :done
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```bash
bundle exec rspec spec/lowmu/input_status_spec.rb --format documentation
```

Expected: All pass.

**Step 5: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

**Step 6: Commit**

```bash
git add lib/lowmu/input_status.rb spec/lowmu/input_status_spec.rb
git commit -m "feat: add InputStatus for per-target status computation"
```

---

## Task 6: Delete `SlugStatus`

**Files:**
- Delete: `lib/lowmu/slug_status.rb`
- Delete: `spec/lowmu/slug_status_spec.rb`

`SlugStatus` is no longer used now that `InputStatus` exists and `Generate` will
be updated in Task 9 to use `InputStatus` instead.

**Step 1: Remove the files**

```bash
git rm lib/lowmu/slug_status.rb spec/lowmu/slug_status_spec.rb
```

**Step 2: Run all tests to confirm nothing is broken**

```bash
bundle exec rspec && bundle exec standardrb
```

`Generate` still uses `SlugStatus` (via `item_status`) — expect failures here.
Note what's failing, then fix `generate.rb` to use `InputStatus` for the
`item_status` helper:

In `lib/lowmu/commands/generate.rb`, update `item_status`:

```ruby
def item_status(item)
  @status_cache ||= {}
  @status_cache[item[:key]] ||= InputStatus.new(item, @config.targets, @store).aggregate
end
```

Also remove the `return false if status == :ignore` line from `should_generate?`
(ignore is gone):

```ruby
def should_generate?(item)
  status = item_status(item)
  return true if @force
  if @key_filter
    status == :pending || status == :stale
  else
    status == :pending
  end
end
```

And update `warn_stale`:

```ruby
def warn_stale(items)
  items.each do |item|
    next unless item_status(item) == :stale
    next if should_generate?(item)
    warn "Warning: '#{item[:key]}' is stale. Run `lowmu generate #{item[:key]}` to regenerate."
  end
end
```

**Step 3: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

Expected: All pass.

**Step 4: Commit**

```bash
git add lib/lowmu/commands/generate.rb
git commit -m "refactor: replace SlugStatus with InputStatus in Generate, delete SlugStatus"
```

---

## Task 7: Rewrite `Commands::Status` with filters and tabular output

**Files:**
- Modify: `lib/lowmu/commands/status.rb`
- Modify: `spec/lowmu/commands/status_spec.rb`

`Commands::Status#call` now returns a matrix suitable for rendering:

```ruby
{
  targets: ["mastodon_short", "substack_long"],    # ordered list of columns
  rows: [
    {key: "long/my-post", statuses: {"mastodon_short" => :done, "substack_long" => :pending}},
    ...
  ]
}
```

Filter options hash has keys: `:all`, `:pending`, `:no_pending`, `:recent`,
`:done`, `:partial`, `:stale`, `:no_stale`. Only one should be set at a time
(CLI enforces this). `:all` is the default when no filter key is set.

`:recent` value is a duration string (e.g. `"1w"`) — filter keeps rows where
at least one output file has mtime within the parsed duration window.

**Step 1: Write the failing spec**

Replace the entire contents of `spec/lowmu/commands/status_spec.rb`:

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
      note_dirs: ["notes"],
      targets: ["mastodon_short", "substack_long"])
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

  def write_output(key, filename, mtime: nil)
    store.ensure_slug_dir(key)
    path = File.join(store.slug_dir(key), filename)
    File.write(path, "generated")
    File.utime(mtime, mtime, path) if mtime
  end

  def call(filters = {})
    described_class.new(nil, config: config, filters: filters).call
  end

  describe "#call" do
    it "returns all targets as column headers" do
      expect(call[:targets]).to eq(["mastodon_short", "substack_long"])
    end

    it "returns a row for every discovered item with no filter" do
      result = call
      expect(result[:rows].map { |r| r[:key] }).to contain_exactly("long/post-a", "short/post-b")
    end

    it "marks substack_long as :not_applicable for short content" do
      result = call
      short_row = result[:rows].find { |r| r[:key] == "short/post-b" }
      expect(short_row[:statuses]["substack_long"]).to eq(:not_applicable)
    end

    context "with --pending filter" do
      it "includes items with at least one pending target" do
        result = call(pending: true)
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes fully done items" do
        past = Time.now - 120
        File.utime(past, past, source_a)
        write_output("long/post-a", "mastodon_short.md")
        write_output("long/post-a", "substack_long.md")
        result = call(pending: true)
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end
    end

    context "with --done filter" do
      it "includes items where all applicable outputs are done" do
        past = Time.now - 120
        File.utime(past, past, source_a)
        write_output("long/post-a", "mastodon_short.md")
        write_output("long/post-a", "substack_long.md")
        result = call(done: true)
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes pending items" do
        result = call(done: true)
        expect(result[:rows]).to be_empty
      end
    end

    context "with --stale filter" do
      it "includes items with at least one stale output" do
        past = Time.now - 120
        write_output("long/post-a", "mastodon_short.md", mtime: past)
        result = call(stale: true)
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end
    end

    context "with --no-stale filter" do
      it "excludes items with any stale output" do
        past = Time.now - 120
        write_output("long/post-a", "mastodon_short.md", mtime: past)
        result = call(no_stale: true)
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end
    end

    context "with --recent filter" do
      it "includes items with output created within the duration" do
        write_output("long/post-a", "mastodon_short.md")
        result = call(recent: "1w")
        expect(result[:rows].map { |r| r[:key] }).to include("long/post-a")
      end

      it "excludes items whose output is older than the duration" do
        old = Time.now - (10 * 86_400)
        write_output("long/post-a", "mastodon_short.md", mtime: old)
        result = call(recent: "3d")
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end

      it "excludes items with no output at all" do
        result = call(recent: "1w")
        expect(result[:rows].map { |r| r[:key] }).not_to include("long/post-a")
      end
    end

    context "with a key filter (specific slug)" do
      it "returns only that item" do
        result = described_class.new("long/post-a", config: config, filters: {}).call
        expect(result[:rows].map { |r| r[:key] }).to contain_exactly("long/post-a")
      end
    end
  end
end
```

**Step 2: Run spec to see failures**

```bash
bundle exec rspec spec/lowmu/commands/status_spec.rb --format documentation
```

Expected: Multiple failures — wrong return shape, missing filters argument.

**Step 3: Rewrite `lib/lowmu/commands/status.rb`**

```ruby
module Lowmu
  module Commands
    class Status
      def initialize(key = nil, config:, filters: {})
        @key_filter = key
        @config = config
        @filters = filters
        @store = ContentStore.new(config.content_dir)
      end

      def call
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter

        rows = items.map do |item|
          statuses = InputStatus.new(item, @config.targets, @store).call
          {key: item[:key], statuses: statuses}
        end

        {targets: @config.targets, rows: filter(rows)}
      end

      private

      def filter(rows)
        return rows if @filters.empty? || @filters[:all]
        rows.select { |row| matches_filter?(row) }
      end

      def matches_filter?(row)
        applicable = row[:statuses].reject { |_, s| s == :not_applicable }
        agg = aggregate(applicable.values)

        return applicable.values.any? { |s| s == :pending } if @filters[:pending]
        return applicable.values.none? { |s| s == :pending } if @filters[:no_pending]
        return agg == :done if @filters[:done]
        return agg == :partial if @filters[:partial]
        return applicable.values.any? { |s| s == :stale } if @filters[:stale]
        return applicable.values.none? { |s| s == :stale } if @filters[:no_stale]
        return recent_match?(row) if @filters[:recent]
        true
      end

      def aggregate(values)
        return :pending if values.none? { |s| s == :done || s == :stale }
        return :stale if values.any? { |s| s == :stale }
        return :done if values.all? { |s| s == :done }
        :partial
      end

      def recent_match?(row)
        duration = DurationParser.parse(@filters[:recent])
        cutoff = Time.now - duration
        @config.targets.any? do |type|
          generator_class = Generators.registry[type]
          output_path = File.join(@store.slug_dir(row[:key]), generator_class::OUTPUT_FILE)
          File.exist?(output_path) && File.mtime(output_path) >= cutoff
        end
      end
    end
  end
end
```

**Step 4: Run spec**

```bash
bundle exec rspec spec/lowmu/commands/status_spec.rb --format documentation
```

Expected: All pass.

**Step 5: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

**Step 6: Commit**

```bash
git add lib/lowmu/commands/status.rb spec/lowmu/commands/status_spec.rb
git commit -m "feat: rewrite Commands::Status with per-target matrix and filter options"
```

---

## Task 8: Update CLI for the new `status` interface

**Files:**
- Modify: `lib/lowmu/cli.rb`
- Modify: `spec/lowmu/cli_spec.rb`

The CLI must:
1. Accept all filter flags (`--all`, `--pending`, `--no-pending`, `--recent`, `--done`, `--partial`, `--stale`, `--no-stale`)
2. Render the tabular output with symbols and a legend
3. Pass a `filters:` hash to `Commands::Status`

**Step 1: Update the cli_spec status tests**

Replace the `describe "#status"` block in `spec/lowmu/cli_spec.rb`:

```ruby
describe "#status" do
  let(:command) { instance_double(Lowmu::Commands::Status) }
  let(:config) { instance_double(Lowmu::Config) }

  before do
    allow(Lowmu::Config).to receive(:load).and_return(config)
    allow(Lowmu::Commands::Status).to receive(:new).and_return(command)
  end

  context "when no content is found" do
    before do
      allow(command).to receive(:call).and_return({targets: [], rows: []})
    end

    it "says no content found" do
      expect { cli.status }.to output(/No content found/).to_stdout
    end
  end

  context "when content exists" do
    before do
      allow(command).to receive(:call).and_return({
        targets: ["mastodon_short"],
        rows: [
          {key: "long/my-post", statuses: {"mastodon_short" => :done}},
          {key: "short/note", statuses: {"mastodon_short" => :pending}}
        ]
      })
    end

    it "prints the input column header" do
      expect { cli.status }.to output(/input/).to_stdout
    end

    it "prints target column headers" do
      expect { cli.status }.to output(/mastodon\/short/).to_stdout
    end

    it "prints the done symbol for done status" do
      expect { cli.status }.to output(/✓/).to_stdout
    end

    it "prints the pending symbol for pending status" do
      expect { cli.status }.to output(/◯/).to_stdout
    end

    it "prints the legend" do
      expect { cli.status }.to output(/done.*pending/m).to_stdout
    end
  end

  context "when Lowmu::Error is raised" do
    before do
      allow(command).to receive(:call).and_raise(Lowmu::Error, "cannot load config")
      allow(cli).to receive(:exit)
    end

    it "prints an error message and exits with code 1" do
      expect { cli.status }.to output(/Error: cannot load config/).to_stdout
      expect(cli).to have_received(:exit).with(1)
    end
  end
end
```

**Step 2: Run cli_spec to see failures**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb -e "status" --format documentation
```

**Step 3: Update `lib/lowmu/cli.rb` — status command**

```ruby
SYMBOLS = {
  done: "✓",
  pending: "◯",
  stale: "⏱",
  not_applicable: "✗"
}.freeze

desc "status [SLUG]", "Report generation status per target"
method_option :all, type: :boolean, desc: "Show all inputs (default)"
method_option :pending, type: :boolean, desc: "At least one output is pending"
method_option :no_pending, type: :boolean, desc: "No pending outputs"
method_option :recent, type: :string, desc: "At least one output within duration (e.g. 1w, 3d)"
method_option :done, type: :boolean, desc: "All applicable outputs are done"
method_option :partial, type: :boolean, desc: "Some but not all outputs are done"
method_option :stale, type: :boolean, desc: "At least one output is stale"
method_option :no_stale, type: :boolean, desc: "No stale outputs"
def status(slug = nil)
  filters = {}
  filters[:pending]    = true if options[:pending]
  filters[:no_pending] = true if options[:no_pending]
  filters[:done]       = true if options[:done]
  filters[:partial]    = true if options[:partial]
  filters[:stale]      = true if options[:stale]
  filters[:no_stale]   = true if options[:no_stale]
  filters[:recent]     = options[:recent] if options[:recent]

  result = Commands::Status.new(slug, config: Config.load, filters: filters).call

  if result[:rows].empty?
    say "No content found."
    return
  end

  render_status_table(result)
rescue Lowmu::Error => e
  error_exit(e.message)
end
```

Add private helper `render_status_table`:

```ruby
def render_status_table(result)
  targets = result[:targets]
  rows = result[:rows]

  # Build column headers: type names rendered as "platform/form"
  target_headers = targets.map { |t| t.sub("_", "/") }
  headers = ["input"] + target_headers

  # Calculate column widths
  col_widths = headers.map(&:length)
  rows.each do |row|
    col_widths[0] = [col_widths[0], row[:key].length].max
  end

  # Render header row
  header_line = headers.each_with_index.map { |h, i| h.ljust(col_widths[i]) }.join(" | ")
  separator   = col_widths.map { |w| "-" * w }.join("-+-")
  say "| #{header_line} |"
  say "+-#{separator}-+"

  # Render data rows
  rows.each do |row|
    cells = [row[:key].ljust(col_widths[0])]
    targets.each_with_index do |type, i|
      sym = SYMBOLS.fetch(row[:statuses][type], "?")
      cells << sym.center(col_widths[i + 1])
    end
    say "| #{cells.join(" | ")} |"
  end

  say ""
  say "#{SYMBOLS[:done]} done  #{SYMBOLS[:pending]} pending  #{SYMBOLS[:not_applicable]} not applicable  #{SYMBOLS[:stale]} stale"
end
```

**Step 4: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

**Step 5: Commit**

```bash
git add lib/lowmu/cli.rb spec/lowmu/cli_spec.rb
git commit -m "feat: update CLI status command with filter flags and tabular output"
```

---

## Task 9: Update `Commands::Generate` — guard, `--recent`, `InputStatus`

**Files:**
- Modify: `lib/lowmu/commands/generate.rb`
- Modify: `spec/lowmu/commands/generate_spec.rb`

Changes:
1. `plan` raises `Lowmu::Error` if no key filter and no `recent_duration` provided
2. `recent_duration` option filters items to those whose source was modified within the duration
3. Remove remaining ignore/`SlugStatus` references (done in Task 6; verify clean)

**Step 1: Write failing tests**

Add to `spec/lowmu/commands/generate_spec.rb`:

```ruby
describe "scope guard" do
  it "raises when called with no slug and no --recent" do
    expect {
      described_class.new(config: config).plan
    }.to raise_error(Lowmu::Error, /--recent/)
  end

  it "does not raise when a slug is given" do
    expect {
      described_class.new("long/my-post", config: config).plan
    }.not_to raise_error
  end

  it "does not raise when --recent is given" do
    expect {
      described_class.new(config: config, recent: "1w").plan
    }.not_to raise_error
  end
end

context "with --recent filter" do
  it "only generates for items modified within the duration" do
    old = Time.now - (10 * 86_400)
    File.utime(old, old, source_path)
    results = described_class.new(config: config, recent: "3d").plan
    expect(results).to be_empty
  end

  it "generates for items modified within the duration" do
    results = described_class.new(config: config, recent: "1w").plan
    expect(results.map { |r| r[:key] }).to include("long/my-post")
  end
end
```

**Step 2: Run tests to see failures**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb -e "scope guard" -e "recent" --format documentation
```

**Step 3: Update `lib/lowmu/commands/generate.rb`**

Add `recent:` parameter to `initialize`:

```ruby
def initialize(key_filter = nil, config:, target: nil, force: false, recent: nil)
  @key_filter = key_filter
  @target_filter = target
  @force = force
  @recent = recent
  @config = config
  @store = ContentStore.new(config.content_dir)
end
```

Update `plan` to add guard and recent filter:

```ruby
def plan
  unless @key_filter || @recent
    raise Error, "Specify a slug or use --recent DURATION to limit scope (e.g. --recent 1w)."
  end
  configure_llm
  items = HugoScanner.new(
    @config.hugo_content_dir,
    post_dirs: @config.post_dirs,
    note_dirs: @config.note_dirs
  ).scan
  items = items.select { |item| item[:key] == @key_filter } if @key_filter
  items = filter_by_recent(items) if @recent
  warn_stale(items)
  items.select { |item| should_generate?(item) }
    .flat_map { |item| plan_item(item) }
end
```

Add private `filter_by_recent`:

```ruby
def filter_by_recent(items)
  duration = DurationParser.parse(@recent)
  cutoff = Time.now - duration
  items.select { |item| File.mtime(item[:source_path]) >= cutoff }
end
```

**Step 4: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

Fix any failures. Note: existing `generate_spec` tests that call `.plan` or `.call`
without a slug or `--recent` must now pass a key or `recent:` option, or they
test the guard behavior.

Update existing `describe "#call"` / `describe "#plan"` contexts that use
`described_class.new(config: config)` to pass `recent: "1w"` or a key so they
don't hit the guard.

**Step 5: Commit**

```bash
git add lib/lowmu/commands/generate.rb spec/lowmu/commands/generate_spec.rb
git commit -m "feat: add scope guard and --recent filter to Commands::Generate"
```

---

## Task 10: Update CLI for `generate --recent`

**Files:**
- Modify: `lib/lowmu/cli.rb`
- Modify: `spec/lowmu/cli_spec.rb`

**Step 1: Add `--recent` option and guard message to the generate command in CLI**

In `lib/lowmu/cli.rb`, update the `generate` method:

```ruby
desc "generate [SLUG]", "Generate platform content from Hugo source"
method_option :target, aliases: "-t", type: :string,
  desc: "Target type to generate. Available: #{Generators::REGISTRY.keys.join(", ") rescue Generators.registry.keys.join(", ")}"
method_option :force, aliases: "-f", type: :boolean, desc: "Force regeneration"
method_option :recent, type: :string, desc: "Only generate for sources modified within duration (e.g. 1w, 3d)"
def generate(slug = nil)
  command = Commands::Generate.new(
    slug,
    target: options[:target],
    force: options[:force],
    recent: options[:recent],
    config: Config.load
  )
  # ... rest unchanged
rescue Lowmu::Error => e
  error_exit(e.message)
end
```

For the `--target` description, since `Generators.registry` is a method (not a constant),
use a proc evaluated at class load time or just write the list statically:

```ruby
method_option :target, aliases: "-t", type: :string,
  desc: "Target type. Available: substack_long, substack_short, mastodon_short, linkedin_short, linkedin_long"
```

**Step 2: Add cli_spec test for guard**

Add to the `describe "#generate"` block in `spec/lowmu/cli_spec.rb`:

```ruby
context "when no slug and no --recent given" do
  before do
    allow(command).to receive(:plan).and_raise(Lowmu::Error, "Specify a slug or use --recent")
    allow(cli).to receive(:exit)
  end

  it "prints the error and exits" do
    expect { cli.generate }.to output(/Specify a slug or use --recent/).to_stdout
    expect(cli).to have_received(:exit).with(1)
  end
end
```

**Step 3: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

**Step 4: Commit**

```bash
git add lib/lowmu/cli.rb spec/lowmu/cli_spec.rb
git commit -m "feat: add --recent option to CLI generate command"
```

---

## Task 11: Update `Commands::Configure` to write new targets format

**Files:**
- Modify: `lib/lowmu/commands/configure.rb`
- Modify: `spec/lowmu/commands/configure_spec.rb`

The configure wizard should write the new flat targets list. Read the current
`configure.rb` and `configure_spec.rb` first to understand the existing structure,
then update the template YAML written to disk to use the new format:

```yaml
targets:
  - substack_long
  - substack_short
  - mastodon_short
  - linkedin_short
  - linkedin_long
```

Also remove any `name:`/`type:` lines from the template.

**Step 1: Read and update**

Read the existing files, update the template string in `configure.rb` to use the
new format, update any fixture or expectation in `configure_spec.rb` that references
the old `name:`/`type:` structure.

**Step 2: Run all tests**

```bash
bundle exec rspec && bundle exec standardrb
```

**Step 3: Commit**

```bash
git add lib/lowmu/commands/configure.rb spec/lowmu/commands/configure_spec.rb
git commit -m "feat: update configure wizard to write simplified targets format"
```

---

## Task 12: Update README

**Files:**
- Modify: `README.md`

Update the example config to show the new `targets:` format. Update the usage
section to show the new `status` filter flags and the `generate --recent` option.
Remove any mention of `ignore.yml`.

```bash
git add README.md
git commit -m "docs: update README for new status filters, generate guard, and targets format"
```

---

## Final verification

```bash
bundle exec rspec --format documentation
bundle exec standardrb
```

Confirm coverage is ≥ 90%. If not, identify uncovered lines and add targeted tests.
