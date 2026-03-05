# Generator Consolidation and Terminology Standardization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename all generators and standardize content type symbols (`:post`/`:note` → `:long`/`:short`) so naming is consistent across the codebase.

**Architecture:** Five generators remain (one per distinct output type), renamed to reflect their output (e.g. `LinkedinArticle` → `LinkedinLong`). Content types change from Hugo-derived names (`:post`, `:note`) to semantic names (`:long`, `:short`) everywhere. Slug directory paths change from `generated/SECTION/SLUG/` to `generated/CONTENT_TYPE/SLUG/`.

**Tech Stack:** Ruby, RSpec, Zeitwerk (autoloads classes from filenames — renaming a file automatically changes the expected class name)

---

### Task 1: LinkedinLong (rename from LinkedinArticle)

**Files:**
- Create: `spec/lowmu/generators/linkedin_long_spec.rb`
- Create: `lib/lowmu/generators/linkedin_long.rb`
- Delete: `spec/lowmu/generators/linkedin_article_spec.rb`
- Delete: `lib/lowmu/generators/linkedin_article.rb`
- Modify: `lib/lowmu/commands/generate.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/generators/linkedin_long_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinLong do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_long_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "linkedin-long", "type" => "linkedin_long"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :long, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    before { mock_llm_response(content: "## LinkedIn Article\n\nContent here.\n\nFollow for more.") }

    it "returns the output filename" do
      expect(generator.generate).to eq("linkedin_long.md")
    end

    it "creates linkedin_long.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "linkedin_long.md"))).to be true
    end

    it "sends a prompt mentioning LinkedIn" do
      mock_chat = mock_llm_response(content: "LinkedIn article")
      generator.generate
      expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/lowmu/generators/linkedin_long_spec.rb
```
Expected: FAIL with `uninitialized constant Lowmu::Generators::LinkedinLong`

**Step 3: Create the implementation**

Create `lib/lowmu/generators/linkedin_long.rb`:

```ruby
module Lowmu
  module Generators
    class LinkedinLong < Base
      FORM = :long
      OUTPUT_FILE = "linkedin_long.md"

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

**Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/lowmu/generators/linkedin_long_spec.rb
```
Expected: PASS (3 examples)

**Step 5: Update GENERATOR_MAP and delete old files**

In `lib/lowmu/commands/generate.rb`, replace:
```ruby
"linkedin_article" => Generators::LinkedinArticle
```
with:
```ruby
"linkedin_long" => Generators::LinkedinLong
```

Delete old files:
```
git rm lib/lowmu/generators/linkedin_article.rb
git rm spec/lowmu/generators/linkedin_article_spec.rb
```

**Step 6: Run full suite to verify nothing broke**

```
bundle exec rspec
```
Expected: all pass

**Step 7: Commit**

```bash
git add lib/lowmu/generators/linkedin_long.rb \
        spec/lowmu/generators/linkedin_long_spec.rb \
        lib/lowmu/commands/generate.rb
git commit -m "refactor: rename LinkedinArticle to LinkedinLong"
```

---

### Task 2: LinkedinShort (rename from LinkedinPost)

**Files:**
- Create: `spec/lowmu/generators/linkedin_short_spec.rb`
- Create: `lib/lowmu/generators/linkedin_short.rb`
- Delete: `spec/lowmu/generators/linkedin_post_spec.rb`
- Delete: `lib/lowmu/generators/linkedin_post.rb`
- Modify: `lib/lowmu/commands/generate.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/generators/linkedin_short_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::LinkedinShort do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_short_test") }
  let(:target_config) { {"name" => "linkedin-short", "type" => "linkedin_short"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with content_type :long" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Professional hook.\n\nKey insight.\n\nRead more: [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :long).generate).to eq("linkedin_short.md")
      end

      it "creates linkedin_short.md" do
        generator(source_path, :long).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_short.md"))).to be true
      end

      it "sends a prompt mentioning LinkedIn" do
        mock_chat = mock_llm_response(content: "LinkedIn post")
        generator(source_path, :long).generate
        expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
      end
    end

    context "with content_type :short" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      before { mock_llm_response(content: "Quick insight on LinkedIn.") }

      it "returns the output filename" do
        expect(generator(source_path, :short).generate).to eq("linkedin_short.md")
      end

      it "creates linkedin_short.md" do
        generator(source_path, :short).generate
        expect(File.exist?(File.join(slug_dir, "linkedin_short.md"))).to be true
      end
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/lowmu/generators/linkedin_short_spec.rb
```
Expected: FAIL with `uninitialized constant Lowmu::Generators::LinkedinShort`

**Step 3: Create the implementation**

Create `lib/lowmu/generators/linkedin_short.rb`:

```ruby
module Lowmu
  module Generators
    class LinkedinShort < Base
      FORM = :short
      OUTPUT_FILE = "linkedin_short.md"

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
        prompt = (@content_type == :short) ? NOTE_PROMPT : POST_PROMPT
        content = ask_llm(prompt % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/lowmu/generators/linkedin_short_spec.rb
```
Expected: PASS (5 examples)

**Step 5: Update GENERATOR_MAP and delete old files**

In `lib/lowmu/commands/generate.rb`, replace:
```ruby
"linkedin_post" => Generators::LinkedinPost,
```
with:
```ruby
"linkedin_short" => Generators::LinkedinShort,
```

```
git rm lib/lowmu/generators/linkedin_post.rb
git rm spec/lowmu/generators/linkedin_post_spec.rb
```

**Step 6: Run full suite**

```
bundle exec rspec
```
Expected: all pass

**Step 7: Commit**

```bash
git add lib/lowmu/generators/linkedin_short.rb \
        spec/lowmu/generators/linkedin_short_spec.rb \
        lib/lowmu/commands/generate.rb
git commit -m "refactor: rename LinkedinPost to LinkedinShort, use :long/:short content types"
```

---

### Task 3: SubstackLong (rename from SubstackNewsletter)

**Files:**
- Create: `spec/lowmu/generators/substack_long_spec.rb`
- Create: `lib/lowmu/generators/substack_long.rb`
- Delete: `spec/lowmu/generators/substack_newsletter_spec.rb`
- Delete: `lib/lowmu/generators/substack_newsletter.rb`
- Modify: `lib/lowmu/commands/generate.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/generators/substack_long_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackLong do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_long_test") }
  let(:source_path) { "spec/fixtures/sample_post.md" }
  let(:target_config) { {"name" => "substack-long", "type" => "substack_long"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator
    described_class.new(slug_dir, source_path, :long, target_config, llm_config)
  end

  it "has FORM :long" do
    expect(described_class::FORM).to eq(:long)
  end

  describe "#generate" do
    it "returns the output filename" do
      expect(generator.generate).to eq("substack_long.md")
    end

    it "creates substack_long.md" do
      generator.generate
      expect(File.exist?(File.join(slug_dir, "substack_long.md"))).to be true
    end

    it "strips front matter from the output" do
      generator.generate
      output = File.read(File.join(slug_dir, "substack_long.md"))
      expect(output).not_to include("title:")
      expect(output).not_to include("---")
    end

    it "preserves the post body content" do
      generator.generate
      output = File.read(File.join(slug_dir, "substack_long.md"))
      expect(output).to include("content of my test post")
    end

    it "does not call the LLM" do
      expect(RubyLLM).not_to receive(:chat)
      generator.generate
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/lowmu/generators/substack_long_spec.rb
```
Expected: FAIL with `uninitialized constant Lowmu::Generators::SubstackLong`

**Step 3: Create the implementation**

Create `lib/lowmu/generators/substack_long.rb`:

```ruby
module Lowmu
  module Generators
    class SubstackLong < Base
      FORM = :long
      OUTPUT_FILE = "substack_long.md"

      def generate
        loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
        parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
        write_output(OUTPUT_FILE, parsed.content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/lowmu/generators/substack_long_spec.rb
```
Expected: PASS (5 examples)

**Step 5: Update GENERATOR_MAP and delete old files**

In `lib/lowmu/commands/generate.rb`, replace:
```ruby
"substack_newsletter" => Generators::SubstackNewsletter,
```
with:
```ruby
"substack_long" => Generators::SubstackLong,
```

```
git rm lib/lowmu/generators/substack_newsletter.rb
git rm spec/lowmu/generators/substack_newsletter_spec.rb
```

**Step 6: Run full suite**

```
bundle exec rspec
```
Expected: all pass

**Step 7: Commit**

```bash
git add lib/lowmu/generators/substack_long.rb \
        spec/lowmu/generators/substack_long_spec.rb \
        lib/lowmu/commands/generate.rb
git commit -m "refactor: rename SubstackNewsletter to SubstackLong"
```

---

### Task 4: SubstackShort (rename from SubstackNote)

**Files:**
- Create: `spec/lowmu/generators/substack_short_spec.rb`
- Create: `lib/lowmu/generators/substack_short.rb`
- Delete: `spec/lowmu/generators/substack_note_spec.rb`
- Delete: `lib/lowmu/generators/substack_note.rb`
- Modify: `lib/lowmu/commands/generate.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/generators/substack_short_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::SubstackShort do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_short_test") }
  let(:target_config) { {"name" => "substack-short", "type" => "substack_short"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with content_type :long" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Short note announcing post. [URL]") }

      it "returns the output filename" do
        expect(generator(source_path, :long).generate).to eq("substack_short.md")
      end

      it "creates substack_short.md" do
        generator(source_path, :long).generate
        expect(File.exist?(File.join(slug_dir, "substack_short.md"))).to be true
      end

      it "calls the LLM to generate a note from the post" do
        mock_chat = mock_llm_response(content: "Note about post. [URL]")
        generator(source_path, :long).generate
        expect(mock_chat).to have_received(:ask).once
      end

      it "sends post content to LLM" do
        mock_chat = mock_llm_response(content: "output")
        generator(source_path, :long).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
      end
    end

    context "with content_type :short" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      it "returns the output filename" do
        expect(generator(source_path, :short).generate).to eq("substack_short.md")
      end

      it "creates substack_short.md" do
        generator(source_path, :short).generate
        expect(File.exist?(File.join(slug_dir, "substack_short.md"))).to be true
      end

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        generator(source_path, :short).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body without front matter" do
        generator(source_path, :short).generate
        content = File.read(File.join(slug_dir, "substack_short.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/lowmu/generators/substack_short_spec.rb
```
Expected: FAIL with `uninitialized constant Lowmu::Generators::SubstackShort`

**Step 3: Create the implementation**

Create `lib/lowmu/generators/substack_short.rb`:

```ruby
module Lowmu
  module Generators
    class SubstackShort < Base
      FORM = :short
      OUTPUT_FILE = "substack_short.md"

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
        if @content_type == :short
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

**Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/lowmu/generators/substack_short_spec.rb
```
Expected: PASS (8 examples)

**Step 5: Update GENERATOR_MAP and delete old files**

In `lib/lowmu/commands/generate.rb`, replace:
```ruby
"substack_note" => Generators::SubstackNote,
```
with:
```ruby
"substack_short" => Generators::SubstackShort,
```

```
git rm lib/lowmu/generators/substack_note.rb
git rm spec/lowmu/generators/substack_note_spec.rb
```

**Step 6: Run full suite**

```
bundle exec rspec
```
Expected: all pass

**Step 7: Commit**

```bash
git add lib/lowmu/generators/substack_short.rb \
        spec/lowmu/generators/substack_short_spec.rb \
        lib/lowmu/commands/generate.rb
git commit -m "refactor: rename SubstackNote to SubstackShort, use :long/:short content types"
```

---

### Task 5: MastodonShort (rename from Mastodon)

**Files:**
- Create: `spec/lowmu/generators/mastodon_short_spec.rb`
- Create: `lib/lowmu/generators/mastodon_short.rb`
- Delete: `spec/lowmu/generators/mastodon_spec.rb`
- Delete: `lib/lowmu/generators/mastodon.rb`
- Modify: `lib/lowmu/commands/generate.rb`

**Step 1: Write the failing spec**

Create `spec/lowmu/generators/mastodon_short_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::Generators::MastodonShort do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon_short_test") }
  let(:target_config) { {"name" => "mastodon", "type" => "mastodon_short"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  def generator(source, content_type = :long)
    described_class.new(slug_dir, source, content_type, target_config, llm_config)
  end

  it "has FORM :short" do
    expect(described_class::FORM).to eq(:short)
  end

  describe "#generate" do
    context "with type: long" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "Interesting post about Ruby! #ruby #testing [URL]") }

      it "returns the output filename" do
        expect(generator(source_path).generate).to eq("mastodon_short.md")
      end

      it "creates mastodon_short.md in the slug directory" do
        generator(source_path).generate
        expect(File.exist?(File.join(slug_dir, "mastodon_short.md"))).to be true
      end

      it "calls the LLM with a prompt mentioning the character limit" do
        mock_chat = mock_llm_response(content: "short post #ruby [URL]")
        generator(source_path).generate
        expect(mock_chat).to have_received(:ask).with(including("500"))
      end

      it "calls the LLM with the full post content" do
        mock_chat = mock_llm_response(content: "post output #ruby [URL]")
        generator(source_path).generate
        expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
      end
    end

    context "with type: short and content within 500 chars" do
      let(:source_path) { "spec/fixtures/sample_note.md" }

      it "does not call the LLM" do
        allow(RubyLLM).to receive(:chat)
        generator(source_path, :short).generate
        expect(RubyLLM).not_to have_received(:chat)
      end

      it "writes the note body (without front matter) to mastodon_short.md" do
        generator(source_path, :short).generate
        content = File.read(File.join(slug_dir, "mastodon_short.md"))
        expect(content).to include("Comparable module")
        expect(content).not_to include("---")
      end
    end

    context "with type: short and content over 500 chars" do
      let(:source_path) do
        path = File.join(slug_dir, "long_note.md")
        File.write(path, "---\ntitle: Long Note\ndate: 2026-03-03\ntype: note\n---\n#{"A" * 501}")
        path
      end

      before { mock_llm_response(content: "Condensed note #ruby [URL]") }

      it "calls the LLM to condense the note" do
        mock_chat = mock_llm_response(content: "Condensed note #ruby [URL]")
        generator(source_path, :short).generate
        expect(mock_chat).to have_received(:ask)
      end
    end

    context "when LLM output exceeds 500 chars" do
      let(:source_path) { "spec/fixtures/sample_post.md" }

      before { mock_llm_response(content: "x" * 501) }

      it "appends a length warning comment to the file" do
        generator(source_path).generate
        content = File.read(File.join(slug_dir, "mastodon_short.md"))
        expect(content).to include("<!-- lowmu:")
        expect(content).to include("500")
      end
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/lowmu/generators/mastodon_short_spec.rb
```
Expected: FAIL with `uninitialized constant Lowmu::Generators::MastodonShort`

**Step 3: Create the implementation**

Create `lib/lowmu/generators/mastodon_short.rb`:

```ruby
module Lowmu
  module Generators
    class MastodonShort < Base
      FORM = :short
      OUTPUT_FILE = "mastodon_short.md"
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
        content = if @content_type == :short
          loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
          parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
          body = parsed.content.strip
          (body.length <= MAX_CHARS) ? body : ask_llm(NOTE_PROMPT % [MAX_CHARS, body])
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

**Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/lowmu/generators/mastodon_short_spec.rb
```
Expected: PASS (8 examples)

**Step 5: Update GENERATOR_MAP and delete old files**

In `lib/lowmu/commands/generate.rb`, replace:
```ruby
"mastodon" => Generators::Mastodon
```
with:
```ruby
"mastodon_short" => Generators::MastodonShort
```

```
git rm lib/lowmu/generators/mastodon.rb
git rm spec/lowmu/generators/mastodon_spec.rb
```

**Step 6: Run full suite**

```
bundle exec rspec
```
Expected: all pass

**Step 7: Commit**

```bash
git add lib/lowmu/generators/mastodon_short.rb \
        spec/lowmu/generators/mastodon_short_spec.rb \
        lib/lowmu/commands/generate.rb
git commit -m "refactor: rename Mastodon to MastodonShort, use :long/:short content types"
```

---

### Task 6: HugoScanner — standardize content type symbols and key format

**Files:**
- Modify: `lib/lowmu/hugo_scanner.rb`
- Modify: `spec/lowmu/hugo_scanner_spec.rb`

**Step 1: Update the failing specs**

In `spec/lowmu/hugo_scanner_spec.rb`, make these changes:

```ruby
# Line 44: change :post to :long
it "tags items from post_dirs with content_type :long" do
  write_md("posts/my-post/index.md")
  result = scanner.scan.first
  expect(result[:content_type]).to eq(:long)
end

# Line 50: change :note to :short
it "tags items from note_dirs with content_type :short" do
  write_md("notes/quick-tip.md")
  result = scanner.scan.first
  expect(result[:content_type]).to eq(:short)
end

# Line 62: key now uses content_type prefix, not section
it "sets key to content_type/slug" do
  write_md("posts/my-post/index.md")
  result = scanner.scan.first
  expect(result[:key]).to eq("long/my-post")
end
```

**Step 2: Run spec to verify it fails**

```
bundle exec rspec spec/lowmu/hugo_scanner_spec.rb
```
Expected: FAIL on the 3 updated examples

**Step 3: Update the implementation**

In `lib/lowmu/hugo_scanner.rb`, change lines 11-12:
```ruby
# before
@post_dirs.each { |dir| results += scan_section(dir, :post) }
@note_dirs.each { |dir| results += scan_section(dir, :note) }

# after
@post_dirs.each { |dir| results += scan_section(dir, :long) }
@note_dirs.each { |dir| results += scan_section(dir, :short) }
```

In `scan_section`, change the key line:
```ruby
# before
key: "#{section}/#{slug}"

# after
key: "#{content_type}/#{slug}"
```

**Step 4: Run spec to verify it passes**

```
bundle exec rspec spec/lowmu/hugo_scanner_spec.rb
```
Expected: all pass

**Step 5: Run full suite**

```
bundle exec rspec
```
Expected: failures in `generate_spec.rb` and `status_spec.rb` (they use old key format — fixed in Task 7)

**Step 6: Commit**

```bash
git add lib/lowmu/hugo_scanner.rb spec/lowmu/hugo_scanner_spec.rb
git commit -m "refactor: standardize content_type symbols to :long/:short in HugoScanner"
```

---

### Task 7: Update generate_spec.rb and status_spec.rb for new keys and type names

**Files:**
- Modify: `spec/lowmu/commands/generate_spec.rb`
- Modify: `spec/lowmu/commands/status_spec.rb`

**Step 1: Update generate_spec.rb**

Change the target let-bindings at the top (lines 12-13):
```ruby
# before
let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon"} }
let(:newsletter_target) { {"name" => "substack-newsletter", "type" => "substack_newsletter"} }

# after
let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon_short"} }
let(:newsletter_target) { {"name" => "substack-long", "type" => "substack_long"} }
```

Change target_config stub (line 30):
```ruby
# before
allow(config).to receive(:target_config).with("substack-newsletter").and_return(newsletter_target)

# after
allow(config).to receive(:target_config).with("substack-long").and_return(newsletter_target)
```

Change `mark_generated` and `mark_stale` output filename (line 40):
```ruby
# before
output = File.join(store.slug_dir(key), "mastodon.txt")

# after
output = File.join(store.slug_dir(key), "mastodon_short.md")
```

Change all occurrences of `"posts/my-post"` key to `"long/my-post"`:
- Line 69: `expect(results.map { |r| r[:key] }).to all(eq("long/my-post"))`
- Line 75: `expect(Dir.exist?(store.slug_dir("long/my-post"))).to be true`
- Lines 101, 130, 188-190: all `"posts/my-post"` → `"long/my-post"`

Change `"notes/my-note"` key to `"short/my-note"` (lines 88-89, 96):
```ruby
note_results = results.select { |r| r[:key] == "short/my-note" }
```

Change target name expectations (lines 63, 89, 96, 175):
```ruby
# before
contain_exactly("mastodon", "substack-newsletter")
# after
contain_exactly("mastodon", "substack-long")
```

**Step 2: Update status_spec.rb**

Change key expectations (line 35):
```ruby
# before
expect(results.map { |r| r[:key] }).to contain_exactly("posts/post-a", "notes/post-b")
# after
expect(results.map { |r| r[:key] }).to contain_exactly("long/post-a", "short/post-b")
```

Change key filter and slug_dir references (lines 46-49, 54-55, 62, 69-70, 76, 84-85, 89):
```ruby
# before: "posts/post-a"
# after:  "long/post-a"
```

Change output filename in before blocks (lines 55, 70):
```ruby
# before
output = File.join(store.slug_dir("posts/post-a"), "mastodon.txt")
# after
output = File.join(store.slug_dir("long/post-a"), "mastodon_short.md")
```

Change ignore.yml key (line 84):
```ruby
# before
File.write(File.join(content_dir, "ignore.yml"), ["posts/post-a"].to_yaml)
# after
File.write(File.join(content_dir, "ignore.yml"), ["long/post-a"].to_yaml)
```

**Step 3: Run specs to verify they pass**

```
bundle exec rspec spec/lowmu/commands/generate_spec.rb spec/lowmu/commands/status_spec.rb
```
Expected: all pass

**Step 4: Run full suite**

```
bundle exec rspec
```
Expected: all pass

**Step 5: Commit**

```bash
git add spec/lowmu/commands/generate_spec.rb spec/lowmu/commands/status_spec.rb
git commit -m "test: update generate and status specs for new key format and generator type names"
```

---

### Task 8: Update config files

**Files:**
- Modify: `spec/fixtures/sample_config.yml`
- Modify: `lib/lowmu/templates/default_config.yml`

**Step 1: Update sample_config.yml**

Replace the targets section:
```yaml
targets:
  - name: linkedin-long
    type: linkedin_long
  - name: linkedin-short
    type: linkedin_short
  - name: mastodon
    type: mastodon_short
    base_url: https://mastodon.social
  - name: substack-long
    type: substack_long
  - name: substack-short
    type: substack_short
```

**Step 2: Update default_config.yml**

Replace the targets section:
```yaml
targets:
  - name: linkedin-long
    type: linkedin_long

  - name: linkedin-short
    type: linkedin_short

  - name: substack-long
    type: substack_long

  - name: substack-short
    type: substack_short

  - name: mastodon
    type: mastodon_short
    base_url: https://mastodon.social
```

**Step 3: Run the full suite one final time**

```
bundle exec rspec
```
Expected: all pass, zero failures

**Step 4: Commit**

```bash
git add spec/fixtures/sample_config.yml lib/lowmu/templates/default_config.yml
git commit -m "chore: update config templates to use standardized generator type names"
```
