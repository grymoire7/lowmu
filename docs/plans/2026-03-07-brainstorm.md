# Brainstorm Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `lowmu brainstorm` command that scans RSS feeds and local markdown files, generates content ideas via AI, and writes them to `$hugo_content_dir/ideas/`.

**Architecture:** Seven new components wired together in `Commands::Brainstorm`: two source readers (`RssSource`, `FileSource`), state tracker (`BrainstormState`), idea file writer (`IdeaWriter`), the command class itself, and a CLI entry point. Config gains `persona` and `sources` accessors. Zeitwerk autoloads everything from existing `lib/lowmu/` tree.

**Tech Stack:** Ruby stdlib `rss` + `open-uri` for RSS parsing; `RubyLLM` (existing) for idea generation; `mock_llm_response` helper (existing) for LLM in specs; fixture XML/markdown files for source specs.

---

### Task 1: Add `persona` and `sources` to `Config`

**Files:**
- Modify: `spec/fixtures/sample_config.yml`
- Modify: `spec/lowmu/config_spec.rb`
- Modify: `lib/lowmu/config.rb`

**Step 1: Add `persona` and `sources` to the fixture**

Add to `spec/fixtures/sample_config.yml`:

```yaml
persona: |
  I write about software engineering and developer tools.

sources:
  - type: rss
    url: https://example.com/feed.xml
    name: example-blog
  - type: file
    path: ~/notes/ideas.md
    name: my-ideas
```

**Step 2: Write the failing tests**

Add to the `RSpec.describe Lowmu::Config` block in `spec/lowmu/config_spec.rb`:

```ruby
describe "#persona" do
  it "returns the persona string" do
    config = described_class.load(fixture_path)
    expect(config.persona).to include("software engineering")
  end

  it "defaults to nil when not set" do
    config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"]})
    expect(config.persona).to be_nil
  end
end

describe "#sources" do
  it "returns an array of source hashes" do
    config = described_class.load(fixture_path)
    expect(config.sources.length).to eq(2)
    expect(config.sources.first["type"]).to eq("rss")
    expect(config.sources.first["name"]).to eq("example-blog")
  end

  it "defaults to empty array when not set" do
    config = described_class.new({"hugo_content_dir" => "/tmp/hugo", "targets" => ["mastodon_short"]})
    expect(config.sources).to eq([])
  end
end
```

**Step 3: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/config_spec.rb -e "persona" -e "sources" --format documentation
```

Expected: FAIL with `undefined method 'persona'`

**Step 4: Update `lib/lowmu/config.rb`**

Add `persona` and `sources` to `attr_reader` and parse them in `initialize`:

```ruby
attr_reader :hugo_content_dir, :content_dir, :llm, :targets, :post_dirs, :note_dirs, :persona, :sources

def initialize(data)
  @hugo_content_dir = File.expand_path(fetch!(data, "hugo_content_dir"))
  @content_dir = File.expand_path(data.fetch("content_dir", ".lowmu"))
  @llm = data.fetch("llm", {})
  @targets = parse_targets(data.fetch("targets", []))
  @post_dirs = data.fetch("post_dirs", ["posts"])
  @note_dirs = data.fetch("note_dirs", ["notes"])
  @persona = data.fetch("persona", nil)
  @sources = data.fetch("sources", [])
end
```

**Step 5: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass, coverage ≥ 90%

**Step 6: Commit**

```bash
git add spec/fixtures/sample_config.yml spec/lowmu/config_spec.rb lib/lowmu/config.rb
git commit -m "feat: add persona and sources to Config"
```

---

### Task 2: `Sources::RssSource`

**Files:**
- Create: `spec/fixtures/sample_feed.xml`
- Create: `spec/lowmu/sources/rss_source_spec.rb`
- Create: `lib/lowmu/sources/rss_source.rb`

**Step 1: Create fixture RSS feed**

Create `spec/fixtures/sample_feed.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Example Blog</title>
    <link>https://example.com</link>
    <description>An example blog</description>
    <item>
      <title>First Post About Ruby</title>
      <link>https://example.com/first-post</link>
      <guid>https://example.com/first-post</guid>
      <description>Ruby is a great language for building tools. It has a clean syntax and a rich ecosystem of gems that make development enjoyable.</description>
    </item>
    <item>
      <title>Second Post About Testing</title>
      <link>https://example.com/second-post</link>
      <guid>https://example.com/second-post</guid>
      <description>Testing is essential for software quality. RSpec makes it easy to write expressive tests in Ruby.</description>
    </item>
  </channel>
</rss>
```

**Step 2: Write the failing spec**

Create `spec/lowmu/sources/rss_source_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Sources::RssSource do
  let(:fixture_xml) { File.read("spec/fixtures/sample_feed.xml") }
  let(:source) { described_class.new(name: "example-blog", url: "https://example.com/feed.xml") }

  before do
    allow(URI).to receive(:open).with("https://example.com/feed.xml").and_return(StringIO.new(fixture_xml))
  end

  describe "#items" do
    it "returns an array of item hashes" do
      expect(source.items).to be_an(Array)
      expect(source.items.length).to eq(2)
    end

    it "includes id, title, excerpt, and source_name" do
      item = source.items.first
      expect(item[:id]).to eq("https://example.com/first-post")
      expect(item[:title]).to eq("First Post About Ruby")
      expect(item[:excerpt]).to include("Ruby is a great language")
      expect(item[:source_name]).to eq("example-blog")
    end

    it "uses link as id when guid is absent" do
      xml = fixture_xml.gsub(/<guid>.*?<\/guid>/, "")
      allow(URI).to receive(:open).and_return(StringIO.new(xml))
      expect(source.items.first[:id]).to eq("https://example.com/first-post")
    end

    it "strips HTML tags from excerpt" do
      xml = fixture_xml.gsub("Ruby is a great language", "<strong>Ruby</strong> is a great language")
      allow(URI).to receive(:open).and_return(StringIO.new(xml))
      expect(source.items.first[:excerpt]).not_to include("<strong>")
      expect(source.items.first[:excerpt]).to include("Ruby")
    end
  end
end
```

**Step 3: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/sources/rss_source_spec.rb --format documentation
```

Expected: FAIL with `uninitialized constant Lowmu::Sources`

**Step 4: Create `lib/lowmu/sources/rss_source.rb`**

```ruby
require "rss"
require "open-uri"

module Lowmu
  module Sources
    class RssSource
      EXCERPT_WORDS = 200

      def initialize(name:, url:)
        @name = name
        @url = url
      end

      def items
        feed = RSS::Parser.parse(URI.open(@url).read, false)
        feed.items.map { |item| parse_item(item) }
      end

      private

      def parse_item(item)
        id = item.guid&.content || item.link
        title = item.title
        body = item.description || ""
        excerpt = strip_html(body).split.first(EXCERPT_WORDS).join(" ")
        {id: id, title: title, excerpt: excerpt, source_name: @name}
      end

      def strip_html(html)
        html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end
    end
  end
end
```

**Step 5: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass

**Step 6: Commit**

```bash
git add spec/fixtures/sample_feed.xml spec/lowmu/sources/rss_source_spec.rb lib/lowmu/sources/rss_source.rb
git commit -m "feat: add Sources::RssSource"
```

---

### Task 3: `Sources::FileSource`

**Files:**
- Create: `spec/fixtures/sample_ideas.md`
- Create: `spec/lowmu/sources/file_source_spec.rb`
- Create: `lib/lowmu/sources/file_source.rb`

**Step 1: Create fixture ideas file**

Create `spec/fixtures/sample_ideas.md`:

```markdown
## Idea One About Ruby Metaprogramming

Ruby's metaprogramming capabilities allow developers to write code that writes code. This enables powerful DSLs and flexible APIs.

## Idea Two About Testing Strategies

Integration tests catch bugs that unit tests miss. A balanced test pyramid combines fast unit tests with targeted integration tests.
```

**Step 2: Write the failing spec**

Create `spec/lowmu/sources/file_source_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Sources::FileSource do
  let(:source) { described_class.new(name: "my-ideas", path: "spec/fixtures/sample_ideas.md") }

  describe "#items" do
    it "returns one item per ## heading" do
      expect(source.items.length).to eq(2)
    end

    it "uses the heading as title" do
      expect(source.items.first[:title]).to eq("Idea One About Ruby Metaprogramming")
    end

    it "includes excerpt from section body" do
      expect(source.items.first[:excerpt]).to include("metaprogramming")
    end

    it "sets source_name" do
      expect(source.items.first[:source_name]).to eq("my-ideas")
    end

    it "generates a stable id from source name and heading" do
      id1 = source.items.first[:id]
      id2 = described_class.new(name: "my-ideas", path: "spec/fixtures/sample_ideas.md").items.first[:id]
      expect(id1).to eq(id2)
    end

    it "generates different ids for different headings" do
      ids = source.items.map { |i| i[:id] }
      expect(ids.uniq.length).to eq(ids.length)
    end
  end
end
```

**Step 3: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/sources/file_source_spec.rb --format documentation
```

Expected: FAIL with `uninitialized constant Lowmu::Sources::FileSource`

**Step 4: Create `lib/lowmu/sources/file_source.rb`**

```ruby
require "digest"

module Lowmu
  module Sources
    class FileSource
      EXCERPT_WORDS = 200

      def initialize(name:, path:)
        @name = name
        @path = File.expand_path(path)
      end

      def items
        content = File.read(@path)
        sections = content.split(/^(?=## )/).reject(&:empty?)
        sections.map { |section| parse_section(section) }
      end

      private

      def parse_section(section)
        lines = section.strip.lines
        title = lines.first.to_s.sub(/^##\s*/, "").strip
        body = lines.drop(1).join.strip
        id = Digest::SHA1.hexdigest("#{@name}:#{title}")[0, 8]
        excerpt = body.split.first(EXCERPT_WORDS).join(" ")
        {id: id, title: title, excerpt: excerpt, source_name: @name}
      end
    end
  end
end
```

**Step 5: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass

**Step 6: Commit**

```bash
git add spec/fixtures/sample_ideas.md spec/lowmu/sources/file_source_spec.rb lib/lowmu/sources/file_source.rb
git commit -m "feat: add Sources::FileSource"
```

---

### Task 4: `BrainstormState`

**Files:**
- Create: `spec/lowmu/brainstorm_state_spec.rb`
- Create: `lib/lowmu/brainstorm_state.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/brainstorm_state_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::BrainstormState do
  let(:content_dir) { Dir.mktmpdir("lowmu_state_test") }
  let(:state) { described_class.new(content_dir) }

  after { FileUtils.rm_rf(content_dir) }

  describe "#seen?" do
    it "returns false for an unknown id" do
      expect(state.seen?("my-source", "abc123")).to be false
    end

    it "returns true after mark_seen" do
      state.mark_seen("my-source", ["abc123"])
      expect(state.seen?("my-source", "abc123")).to be true
    end

    it "returns false for an id from a different source" do
      state.mark_seen("source-a", ["abc123"])
      expect(state.seen?("source-b", "abc123")).to be false
    end
  end

  describe "#mark_seen" do
    it "persists state to disk" do
      state.mark_seen("my-source", ["abc123"])
      reloaded = described_class.new(content_dir)
      expect(reloaded.seen?("my-source", "abc123")).to be true
    end

    it "accumulates ids across calls" do
      state.mark_seen("my-source", ["id1"])
      state.mark_seen("my-source", ["id2"])
      expect(state.seen?("my-source", "id1")).to be true
      expect(state.seen?("my-source", "id2")).to be true
    end

    it "does not duplicate ids" do
      state.mark_seen("my-source", ["id1"])
      state.mark_seen("my-source", ["id1"])
      state_file = YAML.safe_load_file(File.join(content_dir, "brainstorm_state.yml"))
      expect(state_file["sources"]["my-source"]["last_seen_ids"].count("id1")).to eq(1)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/brainstorm_state_spec.rb --format documentation
```

Expected: FAIL with `uninitialized constant Lowmu::BrainstormState`

**Step 3: Create `lib/lowmu/brainstorm_state.rb`**

```ruby
module Lowmu
  class BrainstormState
    def initialize(content_dir)
      @path = File.join(File.expand_path(content_dir), "brainstorm_state.yml")
    end

    def seen?(source_name, id)
      data.dig("sources", source_name, "last_seen_ids")&.include?(id) || false
    end

    def mark_seen(source_name, ids)
      data["sources"] ||= {}
      data["sources"][source_name] ||= {}
      existing = data["sources"][source_name]["last_seen_ids"] || []
      data["sources"][source_name]["last_seen_ids"] = (existing + ids).uniq
      File.write(@path, data.to_yaml)
    end

    private

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

**Step 4: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass

**Step 5: Commit**

```bash
git add spec/lowmu/brainstorm_state_spec.rb lib/lowmu/brainstorm_state.rb
git commit -m "feat: add BrainstormState"
```

---

### Task 5: `IdeaWriter`

**Files:**
- Create: `spec/lowmu/idea_writer_spec.rb`
- Create: `lib/lowmu/idea_writer.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/idea_writer_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::IdeaWriter do
  let(:ideas_dir) { Dir.mktmpdir("lowmu_ideas_test") }
  let(:writer) { described_class.new(ideas_dir) }

  after { FileUtils.rm_rf(ideas_dir) }

  describe "#write" do
    let(:filename) do
      writer.write(
        title: "Ruby Metaprogramming Tips",
        form: "long",
        source_name: "my-blog",
        body: "Here is a great idea about metaprogramming."
      )
    end

    it "returns a filename starting with the form" do
      expect(filename).to start_with("long-")
    end

    it "returns a filename ending with .md" do
      expect(filename).to end_with(".md")
    end

    it "slugifies the title in the filename" do
      expect(filename).to include("ruby-metaprogramming-tips")
    end

    it "creates the file in the ideas directory" do
      expect(File.exist?(File.join(ideas_dir, filename))).to be true
    end

    it "writes YAML front matter with title, form, source, and date" do
      content = File.read(File.join(ideas_dir, filename))
      expect(content).to include("title: \"Ruby Metaprogramming Tips\"")
      expect(content).to include("form: long")
      expect(content).to include("source: my-blog")
      expect(content).to include("date: #{Date.today}")
    end

    it "writes the body after front matter" do
      content = File.read(File.join(ideas_dir, filename))
      expect(content).to include("Here is a great idea about metaprogramming.")
    end

    it "creates the ideas directory if it does not exist" do
      new_dir = File.join(Dir.mktmpdir, "new_ideas")
      described_class.new(new_dir).write(title: "Test", form: "short", source_name: "s", body: "b")
      expect(Dir.exist?(new_dir)).to be true
    end
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/idea_writer_spec.rb --format documentation
```

Expected: FAIL with `uninitialized constant Lowmu::IdeaWriter`

**Step 3: Create `lib/lowmu/idea_writer.rb`**

```ruby
require "date"

module Lowmu
  class IdeaWriter
    def initialize(ideas_dir)
      @ideas_dir = ideas_dir
      FileUtils.mkdir_p(@ideas_dir)
    end

    def write(title:, form:, source_name:, body:)
      slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      filename = "#{form}-#{slug}.md"
      content = <<~MD
        ---
        title: #{title.inspect}
        form: #{form}
        source: #{source_name}
        date: #{Date.today}
        ---

        #{body}
      MD
      File.write(File.join(@ideas_dir, filename), content)
      filename
    end
  end
end
```

**Step 4: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass

**Step 5: Commit**

```bash
git add spec/lowmu/idea_writer_spec.rb lib/lowmu/idea_writer.rb
git commit -m "feat: add IdeaWriter"
```

---

### Task 6: `Commands::Brainstorm`

**Files:**
- Create: `spec/lowmu/commands/brainstorm_spec.rb`
- Create: `lib/lowmu/commands/brainstorm.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/commands/brainstorm_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Commands::Brainstorm do
  let(:hugo_content_dir) { Dir.mktmpdir("lowmu_hugo") }
  let(:content_dir) { Dir.mktmpdir("lowmu_content") }
  let(:notes_file) do
    path = File.join(Dir.mktmpdir, "ideas.md")
    File.write(path, "## Ruby Testing Tips\nGreat ideas about testing.\n\n## Metaprogramming Patterns\nPatterns for Ruby metaprogramming.\n")
    path
  end
  let(:config) do
    instance_double(Lowmu::Config,
      hugo_content_dir: hugo_content_dir,
      content_dir: content_dir,
      llm: {"model" => "claude-opus-4-6"},
      persona: "I write about software engineering.",
      sources: [{"type" => "file", "name" => "my-notes", "path" => notes_file}])
  end
  let(:llm_response) do
    <<~RESPONSE
      IDEA: Testing Ruby Applications
      SOURCE: my-notes
      BODY:
      A comprehensive look at testing strategies for Ruby.

      ---

      IDEA: Effective Metaprogramming
      SOURCE: my-notes
      BODY:
      How to use Ruby metaprogramming without losing your mind.
    RESPONSE
  end

  before do
    mock_llm_response(content: llm_response)
    RubyLLM.configure { |c| c.anthropic_api_key = "test-key" }
  end

  after do
    FileUtils.rm_rf(hugo_content_dir)
    FileUtils.rm_rf(content_dir)
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

    it "writes files to $hugo_content_dir/ideas/" do
      files = described_class.new(config: config, num: 2).call
      ideas_dir = File.join(hugo_content_dir, "ideas")
      expect(File.exist?(File.join(ideas_dir, files.first))).to be true
    end

    it "updates state after generating ideas" do
      described_class.new(config: config, num: 2).call
      state = Lowmu::BrainstormState.new(content_dir)
      expect(state.seen?("my-notes", anything)).to be(true).or be(false)
      # state file should exist
      expect(File.exist?(File.join(content_dir, "brainstorm_state.yml"))).to be true
    end

    it "skips already-seen items by default" do
      # Run once to mark items as seen
      described_class.new(config: config, num: 2).call
      # Second run: no new items, LLM should not be called again
      allow(RubyLLM).to receive(:chat).and_call_original
      expect {
        described_class.new(config: config, num: 2).call
      }.to raise_error(Lowmu::Error, /No new source items/)
    end

    it "processes all items when rescan: true" do
      described_class.new(config: config, num: 2).call
      mock_llm_response(content: llm_response)
      # Should not raise even though items were seen before
      expect {
        described_class.new(config: config, num: 2, rescan: true).call
      }.not_to raise_error
    end

    it "includes persona in the LLM prompt" do
      mock_chat = mock_llm_response(content: llm_response)
      described_class.new(config: config, num: 2).call
      expect(mock_chat).to have_received(:ask).with(including("software engineering"))
    end
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/commands/brainstorm_spec.rb --format documentation
```

Expected: FAIL with `uninitialized constant Lowmu::Commands::Brainstorm`

**Step 3: Create `lib/lowmu/commands/brainstorm.rb`**

```ruby
module Lowmu
  module Commands
    class Brainstorm
      def initialize(config:, form: "long", num: 5, rescan: false)
        @config = config
        @form = form
        @num = num
        @rescan = rescan
        @state = BrainstormState.new(config.content_dir)
        @writer = IdeaWriter.new(File.join(config.hugo_content_dir, "ideas"))
      end

      def call
        configure_llm
        items = gather_items
        raise Error, "No new source items found. Use --rescan to reprocess existing items." if items.empty?

        response = ask_llm(build_prompt(items))
        ideas = parse_response(response)
        files = ideas.map { |idea| @writer.write(**idea) }

        items.group_by { |i| i[:source_name] }.each do |name, source_items|
          @state.mark_seen(name, source_items.map { |i| i[:id] })
        end

        files
      end

      private

      def gather_items
        @config.sources.flat_map do |source|
          all_items = build_source(source).items
          @rescan ? all_items : all_items.reject { |item| @state.seen?(source["name"], item[:id]) }
        end
      end

      def build_source(source)
        case source["type"]
        when "rss" then Sources::RssSource.new(name: source["name"], url: source["url"])
        when "file" then Sources::FileSource.new(name: source["name"], path: source["path"])
        else raise Error, "Unknown source type: #{source["type"]}. Valid types: rss, file"
        end
      end

      def build_prompt(items)
        items_text = items.map { |i| "Source: #{i[:source_name]}\nTitle: #{i[:title]}\n#{i[:excerpt]}" }.join("\n\n---\n\n")
        form_instruction = if @form == "short"
          "Write each idea as a complete ~500 word draft."
        else
          "Write each idea as a one-paragraph summary followed by a list of potential sections."
        end

        <<~PROMPT
          You are helping generate content ideas. Here is the author persona:

          #{@config.persona}

          Here are recent items from idea sources:

          #{items_text}

          Generate #{@num} content ideas for #{@form}-form posts. #{form_instruction}

          For news/current-events items, suggest a specific angle or take.
          For opinion/essay items, use them as inspiration for related ideas.

          Format each idea exactly as:

          IDEA: <title>
          SOURCE: <source name>
          BODY:
          <content>

          ---

          Provide exactly #{@num} ideas, each separated by "---".
        PROMPT
      end

      def parse_response(response)
        blocks = response.split(/^---$/).map(&:strip).reject(&:empty?)
        blocks.first(@num).filter_map do |block|
          title_match = block.match(/^IDEA:\s*(.+)$/)
          source_match = block.match(/^SOURCE:\s*(.+)$/)
          body_match = block.match(/^BODY:\s*\n(.*)/m)
          next unless title_match && body_match
          {
            title: title_match[1].strip,
            source_name: source_match&.[](1)&.strip || "unknown",
            form: @form,
            body: body_match[1].strip
          }
        end
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

**Step 4: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass

**Step 5: Commit**

```bash
git add spec/lowmu/commands/brainstorm_spec.rb lib/lowmu/commands/brainstorm.rb
git commit -m "feat: add Commands::Brainstorm"
```

---

### Task 7: CLI `brainstorm` command

**Files:**
- Modify: `spec/lowmu/cli_spec.rb`
- Modify: `lib/lowmu/cli.rb`

**Step 1: Write the failing CLI tests**

Read `spec/lowmu/cli_spec.rb` first to understand the existing test pattern, then add at the appropriate place:

```ruby
describe "brainstorm" do
  let(:config) do
    instance_double(Lowmu::Config,
      hugo_content_dir: Dir.mktmpdir,
      content_dir: Dir.mktmpdir,
      llm: {"model" => "claude-opus-4-6"},
      persona: "I write about software.",
      sources: [])
  end

  before do
    allow(Lowmu::Config).to receive(:load).and_return(config)
  end

  it "reports the number of generated ideas" do
    allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
      instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md", "long-idea-two.md"])
    )
    expect { CLI.start(["brainstorm"]) }.to output(/Generated 2 ideas/).to_stdout
  end

  it "uses singular when one idea is generated" do
    allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
      instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md"])
    )
    expect { CLI.start(["brainstorm"]) }.to output(/Generated 1 idea\b/).to_stdout
  end

  it "lists the generated filenames" do
    allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
      instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md"])
    )
    expect { CLI.start(["brainstorm"]) }.to output(/long-idea-one\.md/).to_stdout
  end

  it "passes --form to the command" do
    cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: ["short-idea.md"])
    expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(form: "short")).and_return(cmd_double)
    CLI.start(["brainstorm", "--form", "short"])
  end

  it "passes --num to the command" do
    cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: [])
    expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(num: 3)).and_return(cmd_double)
    CLI.start(["brainstorm", "--num", "3"])
  end

  it "passes --rescan to the command" do
    cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: [])
    expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(rescan: true)).and_return(cmd_double)
    CLI.start(["brainstorm", "--rescan"])
  end

  it "prints an error on Lowmu::Error" do
    allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
      instance_double(Lowmu::Commands::Brainstorm, call: nil).tap do |d|
        allow(d).to receive(:call).and_raise(Lowmu::Error, "No new source items found.")
      end
    )
    expect { CLI.start(["brainstorm"]) }.to output(/No new source items found/).to_stdout.and raise_error(SystemExit)
  end
end
```

**Step 2: Run tests to verify they fail**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb -e "brainstorm" --format documentation
```

Expected: FAIL with `Could not find command "brainstorm"`

**Step 3: Add the `brainstorm` command to `lib/lowmu/cli.rb`**

Add before the `private` line:

```ruby
desc "brainstorm", "Generate content ideas from configured sources"
method_option :form, type: :string, default: "long", desc: "Idea form: long or short"
method_option :num, type: :numeric, default: 5, desc: "Number of ideas to generate"
method_option :rescan, type: :boolean, desc: "Ignore state and reprocess all source items"
def brainstorm
  files = Commands::Brainstorm.new(
    config: Config.load,
    form: options[:form],
    num: options[:num],
    rescan: options[:rescan]
  ).call
  say "Generated #{files.count} idea#{files.count == 1 ? "" : "s"}:"
  files.each { |f| say "  #{f}" }
rescue Lowmu::Error => e
  error_exit(e.message)
end
```

**Step 4: Run all tests**

```bash
bundle exec rspec
```

Expected: all pass, coverage ≥ 90%

**Step 5: Commit**

```bash
git add spec/lowmu/cli_spec.rb lib/lowmu/cli.rb
git commit -m "feat: add brainstorm CLI command"
```
