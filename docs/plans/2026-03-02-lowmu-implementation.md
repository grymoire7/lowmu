# lowmu Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the lowmu CLI gem — a Ruby tool for AI-assisted multi-platform content publishing.

**Architecture:** Thor-based CLI with thin command classes delegating to service objects (generators and publishers). Generators use RubyLLM for AI-assisted content transformation. The workflow is split: `generate` writes files to disk for review, `publish` sends them to platforms.

**Tech Stack:** Ruby 3.4.5, Thor (CLI), Zeitwerk (autoloading), RubyLLM ~> 1.12 (AI generation), FrontMatterParser (YAML front matter), RSpec + VCR + WebMock + SimpleCov (testing), StandardRB (formatting)

---

### Task 1: Project Scaffolding

**Files:**
- Create: `lowmu.gemspec`
- Create: `Gemfile`
- Create: `lib/lowmu/version.rb`
- Create: `lib/lowmu.rb`
- Create: `exe/lowmu`
- Create: `.rspec`

**Step 1: Create the version file**

```ruby
# lib/lowmu/version.rb
module Lowmu
  VERSION = "0.1.0"
end
```

**Step 2: Create the gemspec**

```ruby
# lowmu.gemspec
require_relative "lib/lowmu/version"

Gem::Specification.new do |spec|
  spec.name = "lowmu"
  spec.version = Lowmu::VERSION
  spec.authors = ["Tracy Atteberry"]
  spec.summary = "Low friction publishing tool for blog posts and social web content"
  spec.required_ruby_version = ">= 3.4.0"
  spec.files = Dir["lib/**/*", "exe/**/*"]
  spec.bindir = "exe"
  spec.executables = ["lowmu"]

  spec.add_dependency "thor", "~> 1.5"
  spec.add_dependency "ruby_llm", "~> 1.12"
  spec.add_dependency "zeitwerk", "~> 2.7"
  spec.add_dependency "front_matter_parser", "~> 1.0"
end
```

**Step 3: Create the Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "vcr", "~> 6.4"
  gem "webmock", "~> 3.26"
  gem "simplecov", "~> 0.22"
  gem "standard", "~> 1.0"
end
```

**Step 4: Create lib/lowmu.rb**

```ruby
# lib/lowmu.rb
require "zeitwerk"
require "thor"
require "yaml"
require "fileutils"
require "ruby_llm"
require "front_matter_parser"

loader = Zeitwerk::Loader.for_gem
loader.setup

module Lowmu
  class Error < StandardError; end
end
```

**Step 5: Create exe/lowmu**

```ruby
#!/usr/bin/env ruby

require "lowmu"

Lowmu::CLI.start(ARGV)
```

Run: `chmod +x exe/lowmu`

**Step 6: Create .rspec**

```
--require spec_helper
--format documentation
```

**Step 7: Install dependencies and verify**

Run: `bundle install`
Run: `bundle exec ruby -e "require 'lowmu'; puts Lowmu::VERSION"`
Expected: `0.1.0`

**Step 8: Commit**

```bash
git add lowmu.gemspec Gemfile lib/lowmu/version.rb lib/lowmu.rb exe/lowmu .rspec
git commit -m "feat: scaffold gem structure with dependencies"
```

---

### Task 2: Test Infrastructure

**Files:**
- Create: `spec/spec_helper.rb`
- Create: `spec/fixtures/vcr_cassettes/.gitkeep`
- Create: `spec/fixtures/sample_post.md`

**Step 1: Create spec_helper.rb**

```ruby
# spec/spec_helper.rb
require "simplecov"
SimpleCov.start do
  minimum_coverage 90
  add_filter "/spec/"
end

require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<LOWMU_SUBSTACK_API_KEY>") { ENV["LOWMU_SUBSTACK_API_KEY"] }
  config.filter_sensitive_data("<LOWMU_MASTODON_ACCESS_TOKEN>") { ENV["LOWMU_MASTODON_ACCESS_TOKEN"] }
end

require "lowmu"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  config.warnings = true
end
```

**Step 2: Create the sample post fixture**

```markdown
---
title: My Test Post
date: 2026-03-02
type: post
tags: [ruby, testing]
publish_to:
  - tracyatteberry
  - substack
  - mastodon
  - linkedin
---
This is the content of my test post. It talks about Ruby and testing.

## A Section

More content here with some **bold** text and a [link](https://example.com).
```

Save as: `spec/fixtures/sample_post.md`

**Step 3: Verify RSpec runs**

Run: `bundle exec rspec`
Expected: `0 examples, 0 failures`

**Step 4: Commit**

```bash
git add spec/
git commit -m "feat: add RSpec, SimpleCov, and VCR test infrastructure"
```

---

### Task 3: Config Class

**Files:**
- Create: `spec/fixtures/sample_config.yml`
- Create: `spec/lowmu/config_spec.rb`
- Create: `lib/lowmu/config.rb`

**Step 1: Create sample_config.yml fixture**

```yaml
# spec/fixtures/sample_config.yml
content_dir: /tmp/lowmu_test_content

llm:
  provider: anthropic
  model: claude-opus-4-6

targets:
  - name: tracyatteberry
    type: hugo
    base_url: https://tracyatteberry.com
    base_path: /tmp/lowmu_test_hugo
  - name: substack
    type: substack
    auth:
      type: api_key
      api_key: test_api_key
  - name: mastodon
    type: mastodon
    base_url: https://mastodon.social
    auth:
      type: oauth
      access_token: test_access_token
  - name: linkedin
    type: linkedin
```

**Step 2: Write the failing tests**

```ruby
# spec/lowmu/config_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Config do
  let(:fixture_path) { "spec/fixtures/sample_config.yml" }

  describe ".load" do
    it "loads a valid config file" do
      config = described_class.load(fixture_path)
      expect(config).to be_a(described_class)
    end

    it "raises an error when the file does not exist" do
      expect { described_class.load("/nonexistent/config.yml") }
        .to raise_error(Lowmu::Error, /not found/)
    end
  end

  describe "#content_dir" do
    it "returns the expanded content directory path" do
      config = described_class.load(fixture_path)
      expect(config.content_dir).to eq("/tmp/lowmu_test_content")
    end
  end

  describe "#llm" do
    it "returns the llm configuration hash" do
      config = described_class.load(fixture_path)
      expect(config.llm["model"]).to eq("claude-opus-4-6")
    end
  end

  describe "#targets" do
    it "returns all configured targets" do
      config = described_class.load(fixture_path)
      expect(config.targets.length).to eq(4)
    end
  end

  describe "#target_config" do
    it "returns the config hash for a known target" do
      config = described_class.load(fixture_path)
      target = config.target_config("mastodon")
      expect(target["type"]).to eq("mastodon")
    end

    it "raises an error for an unknown target" do
      config = described_class.load(fixture_path)
      expect { config.target_config("nonexistent") }
        .to raise_error(Lowmu::Error, /Unknown target/)
    end
  end

  describe "validation" do
    it "raises when content_dir is missing" do
      expect { described_class.new({}) }
        .to raise_error(Lowmu::Error, /content_dir/)
    end

    it "raises when a target is missing the name key" do
      data = {"content_dir" => "/tmp", "targets" => [{"type" => "hugo"}]}
      expect { described_class.new(data) }
        .to raise_error(Lowmu::Error, /name/)
    end

    it "raises when a target is missing the type key" do
      data = {"content_dir" => "/tmp", "targets" => [{"name" => "myblog"}]}
      expect { described_class.new(data) }
        .to raise_error(Lowmu::Error, /type/)
    end
  end
end
```

**Step 3: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/config_spec.rb`
Expected: FAIL with `uninitialized constant Lowmu::Config`

**Step 4: Implement Config**

```ruby
# lib/lowmu/config.rb
module Lowmu
  class Config
    DEFAULT_PATH = "~/.config/lowmu/config.yml"

    attr_reader :content_dir, :llm, :targets

    def self.load(path = DEFAULT_PATH)
      expanded = File.expand_path(path)
      unless File.exist?(expanded)
        raise Error, "Config file not found at #{expanded}. Run `lowmu configure` to create one."
      end
      data = YAML.safe_load(File.read(expanded)) || {}
      new(data)
    end

    def initialize(data)
      @content_dir = File.expand_path(fetch!(data, "content_dir"))
      @llm = data.fetch("llm", {})
      @targets = parse_targets(data.fetch("targets", []))
    end

    def target_config(name)
      targets.find { |t| t["name"] == name } ||
        raise(Error, "Unknown target: #{name}")
    end

    private

    def fetch!(data, key)
      data.fetch(key) { raise Error, "Config missing required key: #{key}" }
    end

    def parse_targets(targets)
      targets.map do |t|
        raise Error, "Target missing required key: name" unless t["name"]
        raise Error, "Target missing required key: type" unless t["type"]
        t
      end
    end
  end
end
```

**Step 5: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/config_spec.rb`
Expected: All green

**Step 6: Commit**

```bash
git add lib/lowmu/config.rb spec/lowmu/config_spec.rb spec/fixtures/sample_config.yml
git commit -m "feat: add Config class with validation"
```

---

### Task 4: ContentStore

**Files:**
- Create: `spec/lowmu/content_store_spec.rb`
- Create: `lib/lowmu/content_store.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/content_store_spec.rb
require "spec_helper"

RSpec.describe Lowmu::ContentStore do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:store) { described_class.new(base_dir) }

  after { FileUtils.rm_rf(base_dir) }

  describe ".slug_from_path" do
    it "derives slug from a file path" do
      expect(described_class.slug_from_path("/some/path/my-cool-post.md")).to eq("my-cool-post")
    end
  end

  describe "#slug_exists?" do
    it "returns false when slug directory does not exist" do
      expect(store.slug_exists?("my-post")).to be false
    end

    it "returns true when slug directory exists" do
      FileUtils.mkdir_p(File.join(base_dir, "my-post"))
      expect(store.slug_exists?("my-post")).to be true
    end
  end

  describe "#create_slug" do
    let(:md_path) { "spec/fixtures/sample_post.md" }
    let(:image_path) do
      path = File.join(base_dir, "hero.jpg")
      File.write(path, "fake image data")
      path
    end

    it "creates the slug directory" do
      store.create_slug("my-post", md_path, image_path)
      expect(Dir.exist?(File.join(base_dir, "my-post"))).to be true
    end

    it "copies the markdown file as original_content.md" do
      store.create_slug("my-post", md_path, image_path)
      expect(File.exist?(File.join(base_dir, "my-post", "original_content.md"))).to be true
    end

    it "copies the hero image preserving the extension" do
      store.create_slug("my-post", md_path, image_path)
      expect(File.exist?(File.join(base_dir, "my-post", "hero_image.jpg"))).to be true
    end

    it "raises if the slug already exists" do
      FileUtils.mkdir_p(File.join(base_dir, "my-post"))
      expect { store.create_slug("my-post", md_path, image_path) }
        .to raise_error(Lowmu::Error, /already exists/)
    end
  end

  describe "#write_status and #read_status" do
    before { FileUtils.mkdir_p(File.join(base_dir, "my-post")) }

    it "round-trips status data" do
      status = {"substack" => {"status" => "pending"}}
      store.write_status("my-post", status)
      expect(store.read_status("my-post")).to eq(status)
    end

    it "returns empty hash when status file does not exist" do
      expect(store.read_status("my-post")).to eq({})
    end
  end

  describe "#update_target_status" do
    before do
      FileUtils.mkdir_p(File.join(base_dir, "my-post"))
      store.write_status("my-post", {"substack" => {"status" => "pending"}})
    end

    it "merges new attributes into the existing target status" do
      store.update_target_status("my-post", "substack", {"status" => "generated"})
      expect(store.read_status("my-post").dig("substack", "status")).to eq("generated")
    end

    it "preserves existing attributes not being updated" do
      store.update_target_status("my-post", "substack", {"file" => "substack.md"})
      status = store.read_status("my-post")
      expect(status.dig("substack", "status")).to eq("pending")
      expect(status.dig("substack", "file")).to eq("substack.md")
    end
  end

  describe "#slugs" do
    it "returns all slug directory names sorted" do
      FileUtils.mkdir_p(File.join(base_dir, "post-b"))
      FileUtils.mkdir_p(File.join(base_dir, "post-a"))
      expect(store.slugs).to eq(["post-a", "post-b"])
    end

    it "returns empty array when base_dir does not exist" do
      store = described_class.new("/nonexistent/path")
      expect(store.slugs).to eq([])
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/content_store_spec.rb`
Expected: FAIL with `uninitialized constant Lowmu::ContentStore`

**Step 3: Implement ContentStore**

```ruby
# lib/lowmu/content_store.rb
module Lowmu
  class ContentStore
    STATUS_FILE = "status.yml"
    ORIGINAL_CONTENT_FILE = "original_content.md"

    attr_reader :base_dir

    def self.slug_from_path(path)
      File.basename(path, File.extname(path))
    end

    def initialize(base_dir)
      @base_dir = File.expand_path(base_dir)
    end

    def slug_dir(slug)
      File.join(base_dir, slug)
    end

    def slug_exists?(slug)
      Dir.exist?(slug_dir(slug))
    end

    def create_slug(slug, md_path, image_path)
      raise Error, "Slug already exists: #{slug}" if slug_exists?(slug)
      dir = slug_dir(slug)
      FileUtils.mkdir_p(dir)
      FileUtils.cp(md_path, File.join(dir, ORIGINAL_CONTENT_FILE))
      ext = File.extname(image_path)
      FileUtils.cp(image_path, File.join(dir, "hero_image#{ext}"))
    end

    def write_status(slug, status)
      File.write(File.join(slug_dir(slug), STATUS_FILE), status.to_yaml)
    end

    def read_status(slug)
      path = File.join(slug_dir(slug), STATUS_FILE)
      YAML.safe_load(File.read(path)) || {}
    rescue Errno::ENOENT
      {}
    end

    def update_target_status(slug, target_name, status_attrs)
      current = read_status(slug)
      current[target_name] ||= {}
      current[target_name].merge!(status_attrs)
      write_status(slug, current)
    end

    def slugs
      return [] unless Dir.exist?(base_dir)
      Dir.children(base_dir).select { |f| Dir.exist?(File.join(base_dir, f)) }.sort
    end

    def original_content_path(slug)
      File.join(slug_dir(slug), ORIGINAL_CONTENT_FILE)
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/content_store_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/content_store.rb spec/lowmu/content_store_spec.rb
git commit -m "feat: add ContentStore for slug directory management"
```

---

### Task 5: CLI Skeleton + Commands::Configure

**Files:**
- Create: `lib/lowmu/cli.rb`
- Create: `lib/lowmu/commands/configure.rb`
- Create: `spec/lowmu/commands/configure_spec.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/commands/configure_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Commands::Configure do
  let(:config_path) { File.join(Dir.mktmpdir, "config.yml") }

  describe "#call" do
    context "when no config file exists" do
      it "creates the config file" do
        described_class.new(config_path).call
        expect(File.exist?(config_path)).to be true
      end

      it "returns created: true and the path" do
        result = described_class.new(config_path).call
        expect(result[:created]).to be true
        expect(result[:path]).to eq(config_path)
      end

      it "writes a valid YAML template" do
        described_class.new(config_path).call
        data = YAML.safe_load(File.read(config_path))
        expect(data).to have_key("content_dir")
        expect(data).to have_key("targets")
      end
    end

    context "when a config file already exists" do
      before { File.write(config_path, "existing: true\n") }

      it "returns exists: true without overwriting" do
        result = described_class.new(config_path).call
        expect(result[:exists]).to be true
        expect(YAML.safe_load(File.read(config_path))).to eq({"existing" => true})
      end
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/commands/configure_spec.rb`
Expected: FAIL

**Step 3: Implement Configure command**

```ruby
# lib/lowmu/commands/configure.rb
module Lowmu
  module Commands
    class Configure
      CONFIG_TEMPLATE = <<~YAML
        # lowmu configuration file
        # Generated by `lowmu configure`

        # Directory where generated content is stored
        content_dir: ~/projects/lowmu/content

        # LLM configuration for AI-assisted content generation
        llm:
          provider: anthropic
          model: claude-opus-4-6

        # Publishing targets
        targets:
          - name: my-hugo-blog
            type: hugo
            base_url: https://example.com
            base_path: ~/projects/my-blog/content

          - name: substack
            type: substack
            auth:
              type: api_key
              api_key: your_key_here  # or set LOWMU_SUBSTACK_API_KEY

          - name: mastodon
            type: mastodon
            base_url: https://mastodon.social
            auth:
              type: oauth
              access_token: your_token_here  # or set LOWMU_MASTODON_ACCESS_TOKEN

          - name: linkedin
            type: linkedin  # generate-only, no auth needed
      YAML

      def initialize(path = Config::DEFAULT_PATH)
        @path = File.expand_path(path)
      end

      def call
        if File.exist?(@path)
          {exists: true, path: @path}
        else
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, CONFIG_TEMPLATE)
          {created: true, path: @path}
        end
      end
    end
  end
end
```

**Step 4: Create the CLI class**

```ruby
# lib/lowmu/cli.rb
module Lowmu
  class CLI < Thor
    desc "configure", "Create or update the configuration file"
    def configure
      result = Commands::Configure.new.call
      if result[:created]
        say "Config created at #{result[:path]}"
      else
        say "Config already exists at #{result[:path]}"
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "new MD_PATH HERO_IMAGE_PATH", "Register a new post for publishing"
    def new(md_path, hero_image_path)
      result = Commands::New.new(md_path, hero_image_path, config: Config.load).call
      say "Created slug: #{result[:slug]}"
      say "Targets: #{result[:targets].join(", ")}"
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "generate SLUG", "Generate platform-specific content for a slug"
    method_option :target, aliases: "-t", type: :string, desc: "Specific target (default: all)"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force regeneration of existing content"
    def generate(slug)
      results = Commands::Generate.new(
        slug,
        target: options[:target],
        force: options[:force],
        config: Config.load
      ).call
      results.each { |r| say "Generated #{r[:target]}: #{r[:file]}" }
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "status [SLUG]", "Report publishing status"
    def status(slug = nil)
      results = Commands::Status.new(slug, config: Config.load).call
      results.each do |entry|
        say "\n#{entry[:slug]}:"
        entry[:targets].each do |target, data|
          say "  #{target}: #{data["status"]}"
        end
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "publish SLUG", "Publish generated content to configured targets"
    method_option :target, aliases: "-t", type: :string, desc: "Specific target (default: all)"
    def publish(slug)
      results = Commands::Publish.new(
        slug,
        target: options[:target],
        config: Config.load
      ).call
      results.each do |r|
        if r[:status] == :manual
          say "LinkedIn: copy-paste ready at #{r[:file]}"
        else
          say "Published #{r[:target]}"
        end
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    private

    def error_exit(message)
      say "Error: #{message}", :red
      exit(1)
    end
  end
end
```

**Step 5: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/commands/configure_spec.rb`
Expected: All green

**Step 6: Commit**

```bash
git add lib/lowmu/cli.rb lib/lowmu/commands/configure.rb spec/lowmu/commands/configure_spec.rb
git commit -m "feat: add CLI skeleton and Configure command"
```

---

### Task 6: Commands::New

**Files:**
- Create: `spec/lowmu/commands/new_spec.rb`
- Create: `lib/lowmu/commands/new.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/commands/new_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Commands::New do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:config) do
    instance_double(Lowmu::Config,
      content_dir: base_dir,
      targets: [])
  end
  let(:image_path) do
    path = File.join(base_dir, "hero.jpg")
    File.write(path, "fake image")
    path
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    subject(:result) do
      described_class.new("spec/fixtures/sample_post.md", image_path, config: config).call
    end

    it "returns the derived slug" do
      expect(result[:slug]).to eq("sample_post")
    end

    it "returns the publish_to targets from front matter" do
      expect(result[:targets]).to include("substack", "mastodon")
    end

    it "creates the slug directory in content_dir" do
      result
      expect(Dir.exist?(File.join(base_dir, "sample_post"))).to be true
    end

    it "writes initial status.yml with all targets set to pending" do
      result
      store = Lowmu::ContentStore.new(base_dir)
      status = store.read_status("sample_post")
      expect(status["substack"]["status"]).to eq("pending")
      expect(status["mastodon"]["status"]).to eq("pending")
    end

    it "raises if the markdown file does not exist" do
      expect {
        described_class.new("/nonexistent.md", image_path, config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end

    it "raises if the image file does not exist" do
      expect {
        described_class.new("spec/fixtures/sample_post.md", "/nonexistent.jpg", config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/commands/new_spec.rb`
Expected: FAIL with `uninitialized constant Lowmu::Commands::New`

**Step 3: Implement Commands::New**

```ruby
# lib/lowmu/commands/new.rb
module Lowmu
  module Commands
    class New
      def initialize(md_path, hero_image_path, config:)
        @md_path = File.expand_path(md_path)
        @hero_image_path = File.expand_path(hero_image_path)
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        validate!
        slug = ContentStore.slug_from_path(@md_path)
        targets = parse_targets

        @store.create_slug(slug, @md_path, @hero_image_path)

        initial_status = targets.each_with_object({}) do |target, hash|
          hash[target] = {"status" => "pending"}
        end
        @store.write_status(slug, initial_status)

        {slug: slug, targets: targets}
      end

      private

      def validate!
        raise Error, "Markdown file not found: #{@md_path}" unless File.exist?(@md_path)
        raise Error, "Hero image not found: #{@hero_image_path}" unless File.exist?(@hero_image_path)
      end

      def parse_targets
        parsed = FrontMatterParser::Parser.parse_file(@md_path)
        parsed.front_matter.fetch("publish_to", [])
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/commands/new_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/commands/new.rb spec/lowmu/commands/new_spec.rb
git commit -m "feat: add Commands::New for registering new posts"
```

---

### Task 7: Generators::Base

**Files:**
- Create: `lib/lowmu/generators/base.rb`

No dedicated spec for Base — it's abstract. It will be exercised through subclass tests.

```ruby
# lib/lowmu/generators/base.rb
module Lowmu
  module Generators
    class Base
      def initialize(slug_dir, target_config, llm_config)
        @slug_dir = slug_dir
        @target_config = target_config
        @llm_config = llm_config
      end

      def generate
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      private

      def original_content
        @original_content ||= File.read(File.join(@slug_dir, ContentStore::ORIGINAL_CONTENT_FILE))
      end

      def write_output(filename, content)
        File.write(File.join(@slug_dir, filename), content)
      end

      def ask_llm(prompt)
        model = @llm_config.fetch("model", "claude-opus-4-6")
        RubyLLM.chat(model: model).ask(prompt).content
      end
    end
  end
end
```

**Commit:**

```bash
git add lib/lowmu/generators/base.rb
git commit -m "feat: add Generators::Base abstract class"
```

---

### Task 8: Generators::Hugo

Hugo generation is a pure format transform — no LLM needed. It adjusts front matter for Hugo compatibility and passes the content through unchanged.

**Files:**
- Create: `spec/lowmu/generators/hugo_spec.rb`
- Create: `lib/lowmu/generators/hugo.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/generators/hugo_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Generators::Hugo do
  let(:slug_dir) { Dir.mktmpdir("lowmu_hugo_test") }
  let(:target_config) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => "/tmp/hugo"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    subject(:output_file) do
      described_class.new(slug_dir, target_config, llm_config).generate
    end

    it "returns the output filename" do
      expect(output_file).to eq("hugo.md")
    end

    it "creates hugo.md in the slug directory" do
      output_file
      expect(File.exist?(File.join(slug_dir, "hugo.md"))).to be true
    end

    it "includes the title from front matter" do
      output_file
      content = File.read(File.join(slug_dir, "hugo.md"))
      expect(content).to include("title: My Test Post")
    end

    it "includes the post body content" do
      output_file
      content = File.read(File.join(slug_dir, "hugo.md"))
      expect(content).to include("content of my test post")
    end

    it "does not include publish_to in the Hugo front matter" do
      output_file
      content = File.read(File.join(slug_dir, "hugo.md"))
      expect(content).not_to include("publish_to")
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/generators/hugo_spec.rb`
Expected: FAIL

**Step 3: Implement Generators::Hugo**

```ruby
# lib/lowmu/generators/hugo.rb
module Lowmu
  module Generators
    class Hugo < Base
      OUTPUT_FILE = "hugo.md"

      FRONT_MATTER_KEYS = %w[title date tags draft].freeze

      def generate
        parsed = FrontMatterParser::Parser.parse_string(original_content)
        fm = parsed.front_matter

        hugo_fm = fm.slice(*FRONT_MATTER_KEYS).merge("draft" => false)
        output = "---\n#{hugo_fm.to_yaml.sub(/\A---\n/, "")}---\n\n#{parsed.content.strip}\n"

        write_output(OUTPUT_FILE, output)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/generators/hugo_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/generators/hugo.rb spec/lowmu/generators/hugo_spec.rb
git commit -m "feat: add Hugo generator with front matter transformation"
```

---

### Task 9: Generators::Substack

Uses RubyLLM. Unit tests use instance doubles; integration-style tests use VCR cassettes.

**Files:**
- Create: `spec/support/ruby_llm_helpers.rb`
- Create: `spec/lowmu/generators/substack_spec.rb`
- Create: `lib/lowmu/generators/substack.rb`

**Step 1: Create shared RubyLLM test helper**

```ruby
# spec/support/ruby_llm_helpers.rb
module RubyLlmHelpers
  def mock_llm_response(content:)
    mock_response = instance_double(RubyLLM::Message, content: content)
    mock_chat = instance_double(RubyLLM::Chat, ask: mock_response)
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    mock_chat
  end
end

RSpec.configure do |config|
  config.include RubyLlmHelpers
end
```

Add to `spec/spec_helper.rb` (after the existing requires):

```ruby
Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }
```

**Step 2: Write the failing tests**

```ruby
# spec/lowmu/generators/substack_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Generators::Substack do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack_test") }
  let(:target_config) { {"name" => "substack", "type" => "substack"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    before { mock_llm_response(content: "# My Test Post\n\nFormatted for Substack.") }

    it "returns the output filename" do
      result = described_class.new(slug_dir, target_config, llm_config).generate
      expect(result).to eq("substack.md")
    end

    it "creates substack.md in the slug directory" do
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(File.exist?(File.join(slug_dir, "substack.md"))).to be true
    end

    it "writes the LLM response to substack.md" do
      described_class.new(slug_dir, target_config, llm_config).generate
      content = File.read(File.join(slug_dir, "substack.md"))
      expect(content).to include("Formatted for Substack")
    end

    it "sends the original content to the LLM" do
      mock_chat = mock_llm_response(content: "output")
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(mock_chat).to have_received(:ask).with(including("content of my test post"))
    end
  end
end
```

**Step 3: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/generators/substack_spec.rb`
Expected: FAIL

**Step 4: Implement Generators::Substack**

```ruby
# lib/lowmu/generators/substack.rb
module Lowmu
  module Generators
    class Substack < Base
      OUTPUT_FILE = "substack.md"

      PROMPT = <<~PROMPT
        Reformat the following markdown blog post for publication on Substack.
        Keep the full content intact. Ensure the markdown is clean and readable.
        Remove any Hugo-specific front matter fields — return only the body content
        with no front matter at all. Preserve the author's voice and tone exactly.

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

**Step 5: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/generators/substack_spec.rb`
Expected: All green

**Step 6: Commit**

```bash
git add lib/lowmu/generators/substack.rb spec/lowmu/generators/substack_spec.rb spec/support/ruby_llm_helpers.rb spec/spec_helper.rb
git commit -m "feat: add Substack generator with LLM-assisted formatting"
```

---

### Task 10: Generators::Mastodon

Follows the same pattern as Generators::Substack. Mastodon posts must be under 500 characters and include hashtags.

**Files:**
- Create: `spec/lowmu/generators/mastodon_spec.rb`
- Create: `lib/lowmu/generators/mastodon.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/generators/mastodon_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Generators::Mastodon do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon_test") }
  let(:target_config) { {"name" => "mastodon", "type" => "mastodon"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    before do
      mock_llm_response(content: "Interesting post about Ruby! #ruby #testing [URL]")
    end

    it "returns the output filename" do
      result = described_class.new(slug_dir, target_config, llm_config).generate
      expect(result).to eq("mastodon.txt")
    end

    it "creates mastodon.txt in the slug directory" do
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(File.exist?(File.join(slug_dir, "mastodon.txt"))).to be true
    end

    it "sends a prompt mentioning the character limit" do
      mock_chat = mock_llm_response(content: "short post #ruby [URL]")
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(mock_chat).to have_received(:ask).with(including("500"))
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/generators/mastodon_spec.rb`
Expected: FAIL

**Step 3: Implement Generators::Mastodon**

```ruby
# lib/lowmu/generators/mastodon.rb
module Lowmu
  module Generators
    class Mastodon < Base
      OUTPUT_FILE = "mastodon.txt"
      MAX_CHARS = 500

      PROMPT = <<~PROMPT
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

      def generate
        content = ask_llm(PROMPT % [MAX_CHARS, original_content])
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/generators/mastodon_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/generators/mastodon.rb spec/lowmu/generators/mastodon_spec.rb
git commit -m "feat: add Mastodon generator with character-limit-aware prompt"
```

---

### Task 11: Generators::LinkedIn

Same pattern. LinkedIn posts are professional, 150-300 words, with a strong opening hook.

**Files:**
- Create: `spec/lowmu/generators/linkedin_spec.rb`
- Create: `lib/lowmu/generators/linkedin.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/generators/linkedin_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Generators::Linkedin do
  let(:slug_dir) { Dir.mktmpdir("lowmu_linkedin_test") }
  let(:target_config) { {"name" => "linkedin", "type" => "linkedin"} }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }

  after { FileUtils.rm_rf(slug_dir) }

  before do
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
  end

  describe "#generate" do
    before do
      mock_llm_response(content: "Professional hook line.\n\nKey insight here.\n\nRead more: [URL]")
    end

    it "returns the output filename" do
      result = described_class.new(slug_dir, target_config, llm_config).generate
      expect(result).to eq("linkedin.md")
    end

    it "creates linkedin.md in the slug directory" do
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(File.exist?(File.join(slug_dir, "linkedin.md"))).to be true
    end

    it "sends a prompt mentioning LinkedIn" do
      mock_chat = mock_llm_response(content: "LinkedIn post")
      described_class.new(slug_dir, target_config, llm_config).generate
      expect(mock_chat).to have_received(:ask).with(including("LinkedIn"))
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/generators/linkedin_spec.rb`
Expected: FAIL

**Step 3: Implement Generators::LinkedIn**

```ruby
# lib/lowmu/generators/linkedin.rb
module Lowmu
  module Generators
    class Linkedin < Base
      OUTPUT_FILE = "linkedin.md"

      PROMPT = <<~PROMPT
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

      def generate
        content = ask_llm(PROMPT % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/generators/linkedin_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/generators/linkedin.rb spec/lowmu/generators/linkedin_spec.rb
git commit -m "feat: add LinkedIn generator with professional tone prompt"
```

---

### Task 12: Commands::Generate

**Files:**
- Create: `spec/lowmu/commands/generate_spec.rb`
- Create: `lib/lowmu/commands/generate.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/commands/generate_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Commands::Generate do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:slug) { "sample_post" }
  let(:slug_dir) { File.join(base_dir, slug) }
  let(:llm_config) { {"model" => "claude-opus-4-6"} }
  let(:hugo_target) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => "/tmp"} }
  let(:mastodon_target) { {"name" => "mastodon", "type" => "mastodon"} }

  let(:config) do
    instance_double(Lowmu::Config,
      content_dir: base_dir,
      llm: llm_config,
      target_config: nil)
  end

  before do
    FileUtils.mkdir_p(slug_dir)
    FileUtils.cp("spec/fixtures/sample_post.md",
      File.join(slug_dir, Lowmu::ContentStore::ORIGINAL_CONTENT_FILE))
    store = Lowmu::ContentStore.new(base_dir)
    store.write_status(slug, {
      "tracyatteberry" => {"status" => "pending"},
      "mastodon" => {"status" => "pending"}
    })
    allow(config).to receive(:target_config).with("tracyatteberry").and_return(hugo_target)
    allow(config).to receive(:target_config).with("mastodon").and_return(mastodon_target)
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    context "without --target flag" do
      it "generates content for all pending targets" do
        mock_llm_response(content: "Mastodon post #ruby [URL]")
        results = described_class.new(slug, config: config).call
        expect(results.map { |r| r[:target] }).to contain_exactly("tracyatteberry", "mastodon")
      end

      it "updates status to generated for each target" do
        mock_llm_response(content: "post content")
        described_class.new(slug, config: config).call
        store = Lowmu::ContentStore.new(base_dir)
        expect(store.read_status(slug).dig("tracyatteberry", "status")).to eq("generated")
      end
    end

    context "with --target flag" do
      it "generates content only for the specified target" do
        results = described_class.new(slug, target: "tracyatteberry", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:target]).to eq("tracyatteberry")
      end

      it "raises for an unknown target" do
        expect {
          described_class.new(slug, target: "unknown", config: config).call
        }.to raise_error(Lowmu::Error, /not in publish_to/)
      end
    end

    context "with already-generated content" do
      before do
        store = Lowmu::ContentStore.new(base_dir)
        store.update_target_status(slug, "tracyatteberry", {"status" => "generated"})
      end

      it "raises without --force" do
        expect {
          described_class.new(slug, target: "tracyatteberry", config: config).call
        }.to raise_error(Lowmu::Error, /already generated/)
      end

      it "regenerates with --force" do
        result = described_class.new(slug, target: "tracyatteberry", force: true, config: config).call
        expect(result.first[:target]).to eq("tracyatteberry")
      end
    end

    it "raises if the slug does not exist" do
      expect {
        described_class.new("nonexistent", config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/commands/generate_spec.rb`
Expected: FAIL

**Step 3: Implement Commands::Generate**

```ruby
# lib/lowmu/commands/generate.rb
module Lowmu
  module Commands
    class Generate
      GENERATOR_MAP = {
        "hugo" => Generators::Hugo,
        "substack" => Generators::Substack,
        "mastodon" => Generators::Mastodon,
        "linkedin" => Generators::Linkedin
      }.freeze

      def initialize(slug, target: nil, force: false, config:)
        @slug = slug
        @target_filter = target
        @force = force
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        raise Error, "Slug not found: #{@slug}" unless @store.slug_exists?(@slug)

        configure_llm
        resolve_targets.map { |target_name| generate_target(target_name) }
      end

      private

      def generate_target(target_name)
        target_config = @config.target_config(target_name)
        current_status = @store.read_status(@slug).dig(target_name, "status")

        if current_status == "generated" && !@force
          raise Error, "Target '#{target_name}' already generated. Use --force to regenerate."
        end

        generator_class = GENERATOR_MAP.fetch(target_config["type"]) do
          raise Error, "Unknown target type: #{target_config["type"]}"
        end

        output_file = generator_class.new(@store.slug_dir(@slug), target_config, @config.llm).generate
        @store.update_target_status(@slug, target_name, {"status" => "generated", "file" => output_file})

        {target: target_name, file: output_file}
      end

      def resolve_targets
        all_targets = @store.read_status(@slug).keys

        if @target_filter
          raise Error, "Target '#{@target_filter}' not in publish_to list" unless all_targets.include?(@target_filter)
          [@target_filter]
        else
          all_targets
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

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/commands/generate_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/commands/generate.rb spec/lowmu/commands/generate_spec.rb
git commit -m "feat: add Commands::Generate with --target and --force support"
```

---

### Task 13: Commands::Status

**Files:**
- Create: `spec/lowmu/commands/status_spec.rb`
- Create: `lib/lowmu/commands/status.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/commands/status_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Commands::Status do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:config) { instance_double(Lowmu::Config, content_dir: base_dir) }

  before do
    store = Lowmu::ContentStore.new(base_dir)
    FileUtils.mkdir_p(File.join(base_dir, "post-a"))
    FileUtils.mkdir_p(File.join(base_dir, "post-b"))
    store.write_status("post-a", {"substack" => {"status" => "generated"}})
    store.write_status("post-b", {"mastodon" => {"status" => "published"}})
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    context "without a slug" do
      it "returns an entry for every slug" do
        results = described_class.new(nil, config: config).call
        slugs = results.map { |r| r[:slug] }
        expect(slugs).to contain_exactly("post-a", "post-b")
      end
    end

    context "with a specific slug" do
      it "returns only that slug's entry" do
        results = described_class.new("post-a", config: config).call
        expect(results.length).to eq(1)
        expect(results.first[:slug]).to eq("post-a")
      end

      it "includes target statuses" do
        results = described_class.new("post-a", config: config).call
        expect(results.first[:targets].dig("substack", "status")).to eq("generated")
      end
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/commands/status_spec.rb`
Expected: FAIL

**Step 3: Implement Commands::Status**

```ruby
# lib/lowmu/commands/status.rb
module Lowmu
  module Commands
    class Status
      def initialize(slug = nil, config:)
        @slug = slug
        @store = ContentStore.new(config.content_dir)
      end

      def call
        slugs = @slug ? [@slug] : @store.slugs
        slugs.map do |s|
          {slug: s, targets: @store.read_status(s)}
        end
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/commands/status_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/commands/status.rb spec/lowmu/commands/status_spec.rb
git commit -m "feat: add Commands::Status for publishing status reporting"
```

---

### Task 14: Publishers::Base + Publishers::Hugo

Hugo publishing copies generated files to the Hugo content directory.

**Files:**
- Create: `lib/lowmu/publishers/base.rb`
- Create: `spec/lowmu/publishers/hugo_spec.rb`
- Create: `lib/lowmu/publishers/hugo.rb`

**Step 1: Create Publishers::Base**

```ruby
# lib/lowmu/publishers/base.rb
module Lowmu
  module Publishers
    class Base
      def initialize(slug_dir, target_config)
        @slug_dir = slug_dir
        @target_config = target_config
      end

      def publish
        raise NotImplementedError, "#{self.class} must implement #publish"
      end

      private

      def generated_file_path(filename)
        path = File.join(@slug_dir, filename)
        raise Error, "Generated file not found: #{filename}. Run `lowmu generate` first." unless File.exist?(path)
        path
      end
    end
  end
end
```

**Step 2: Write the failing tests for Hugo publisher**

```ruby
# spec/lowmu/publishers/hugo_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Publishers::Hugo do
  let(:slug_dir) { Dir.mktmpdir("lowmu_slug") }
  let(:hugo_base) { Dir.mktmpdir("lowmu_hugo") }
  let(:target_config) do
    {"name" => "tracyatteberry", "type" => "hugo", "base_path" => hugo_base}
  end

  after do
    FileUtils.rm_rf(slug_dir)
    FileUtils.rm_rf(hugo_base)
  end

  before do
    File.write(File.join(slug_dir, "hugo.md"), "# Generated Hugo post")
    File.write(File.join(slug_dir, "hero_image.jpg"), "fake image")
  end

  describe "#publish" do
    subject(:dest_dir) { described_class.new(slug_dir, target_config).publish }

    it "returns the destination directory path" do
      expect(dest_dir).to be_a(String)
      expect(Dir.exist?(dest_dir)).to be true
    end

    it "copies hugo.md to the destination as index.md" do
      dest_dir
      expect(File.exist?(File.join(dest_dir, "index.md"))).to be true
    end

    it "copies the hero image to the destination" do
      dest_dir
      expect(File.exist?(File.join(dest_dir, "hero_image.jpg"))).to be true
    end

    it "raises if hugo.md has not been generated" do
      FileUtils.rm(File.join(slug_dir, "hugo.md"))
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /not found/)
    end
  end
end
```

**Step 3: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/publishers/hugo_spec.rb`
Expected: FAIL

**Step 4: Implement Publishers::Hugo**

```ruby
# lib/lowmu/publishers/hugo.rb
module Lowmu
  module Publishers
    class Hugo < Base
      def publish
        slug = File.basename(@slug_dir)
        base_path = File.expand_path(@target_config["base_path"])
        dest_dir = File.join(base_path, "posts", slug)

        FileUtils.mkdir_p(dest_dir)
        FileUtils.cp(generated_file_path(Generators::Hugo::OUTPUT_FILE), File.join(dest_dir, "index.md"))

        hero = Dir[File.join(@slug_dir, "hero_image.*")].first
        FileUtils.cp(hero, File.join(dest_dir, File.basename(hero))) if hero

        dest_dir
      end
    end
  end
end
```

**Step 5: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/publishers/hugo_spec.rb`
Expected: All green

**Step 6: Commit**

```bash
git add lib/lowmu/publishers/base.rb lib/lowmu/publishers/hugo.rb spec/lowmu/publishers/hugo_spec.rb
git commit -m "feat: add Publishers::Base and Publishers::Hugo for file copy publishing"
```

---

### Task 15: Publishers::Mastodon

Posts to the Mastodon API using the `/api/v1/statuses` endpoint. Uses VCR cassette for integration test.

**Files:**
- Create: `spec/lowmu/publishers/mastodon_spec.rb`
- Create: `lib/lowmu/publishers/mastodon.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/publishers/mastodon_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Publishers::Mastodon do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon") }
  let(:target_config) do
    {
      "name" => "mastodon",
      "type" => "mastodon",
      "base_url" => "https://mastodon.social",
      "auth" => {"access_token" => "test_token"}
    }
  end

  after { FileUtils.rm_rf(slug_dir) }

  before do
    File.write(File.join(slug_dir, "mastodon.txt"), "Test post #ruby [URL]")
  end

  describe "#publish" do
    context "with a successful API response" do
      before do
        stub_request(:post, "https://mastodon.social/api/v1/statuses")
          .to_return(
            status: 200,
            body: JSON.generate({"url" => "https://mastodon.social/@user/123"}),
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "returns the URL of the published post" do
        result = described_class.new(slug_dir, target_config).publish
        expect(result).to eq("https://mastodon.social/@user/123")
      end

      it "sends the post content in the request body" do
        described_class.new(slug_dir, target_config).publish
        expect(WebMock).to have_requested(:post, "https://mastodon.social/api/v1/statuses")
          .with(body: hash_including("status" => "Test post #ruby [URL]"))
      end
    end

    context "with an API error" do
      before do
        stub_request(:post, "https://mastodon.social/api/v1/statuses")
          .to_return(status: 401, body: "Unauthorized")
      end

      it "raises an error" do
        expect { described_class.new(slug_dir, target_config).publish }
          .to raise_error(Lowmu::Error, /Mastodon API error/)
      end
    end

    it "raises if mastodon.txt has not been generated" do
      FileUtils.rm(File.join(slug_dir, "mastodon.txt"))
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /not found/)
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/publishers/mastodon_spec.rb`
Expected: FAIL

**Step 3: Implement Publishers::Mastodon**

```ruby
# lib/lowmu/publishers/mastodon.rb
require "net/http"
require "json"

module Lowmu
  module Publishers
    class Mastodon < Base
      def publish
        content = File.read(generated_file_path(Generators::Mastodon::OUTPUT_FILE))
        response = post_status(content)

        unless response.code == "200"
          raise Error, "Mastodon API error (#{response.code}): #{response.body}"
        end

        JSON.parse(response.body)["url"]
      end

      private

      def post_status(content)
        uri = URI("#{base_url}/api/v1/statuses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate({"status" => content})

        http.request(request)
      end

      def base_url
        @target_config["base_url"]
      end

      def access_token
        ENV.fetch("LOWMU_MASTODON_ACCESS_TOKEN", nil) ||
          @target_config.dig("auth", "access_token") ||
          raise(Error, "Mastodon access token not configured")
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/publishers/mastodon_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/publishers/mastodon.rb spec/lowmu/publishers/mastodon_spec.rb
git commit -m "feat: add Mastodon publisher using /api/v1/statuses"
```

---

### Task 16: Publishers::Substack

> **Note:** Substack does not have a public publishing API. This publisher is a stub that raises a clear error. Implement when/if an official API becomes available, or replace with browser automation.

**Files:**
- Create: `lib/lowmu/publishers/substack.rb`
- Create: `spec/lowmu/publishers/substack_spec.rb`

**Step 1: Write the test**

```ruby
# spec/lowmu/publishers/substack_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Publishers::Substack do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack") }
  let(:target_config) { {"name" => "substack", "type" => "substack"} }

  after { FileUtils.rm_rf(slug_dir) }

  describe "#publish" do
    it "raises a NotImplementedError with a helpful message" do
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /Substack.*not yet supported/)
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/publishers/substack_spec.rb`
Expected: FAIL

**Step 3: Implement stub**

```ruby
# lib/lowmu/publishers/substack.rb
module Lowmu
  module Publishers
    class Substack < Base
      def publish
        raise Error, "Substack direct publishing is not yet supported. " \
          "Your generated content is at: #{File.join(@slug_dir, Generators::Substack::OUTPUT_FILE)}"
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/publishers/substack_spec.rb`
Expected: All green

**Step 5: Commit**

```bash
git add lib/lowmu/publishers/substack.rb spec/lowmu/publishers/substack_spec.rb
git commit -m "feat: add Substack publisher stub with helpful error message"
```

---

### Task 17: Commands::Publish

**Files:**
- Create: `spec/lowmu/commands/publish_spec.rb`
- Create: `lib/lowmu/commands/publish.rb`

**Step 1: Write the failing tests**

```ruby
# spec/lowmu/commands/publish_spec.rb
require "spec_helper"

RSpec.describe Lowmu::Commands::Publish do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:slug) { "my-post" }
  let(:slug_dir) { File.join(base_dir, slug) }

  let(:hugo_target) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => base_dir} }
  let(:linkedin_target) { {"name" => "linkedin", "type" => "linkedin"} }

  let(:config) do
    instance_double(Lowmu::Config, content_dir: base_dir)
  end

  before do
    FileUtils.mkdir_p(slug_dir)
    File.write(File.join(slug_dir, "hugo.md"), "# Hugo post")
    File.write(File.join(slug_dir, "hero_image.jpg"), "fake image")
    File.write(File.join(slug_dir, "linkedin.md"), "LinkedIn post content")

    store = Lowmu::ContentStore.new(base_dir)
    store.write_status(slug, {
      "tracyatteberry" => {"status" => "generated"},
      "linkedin" => {"status" => "generated"}
    })

    allow(config).to receive(:target_config).with("tracyatteberry").and_return(hugo_target)
    allow(config).to receive(:target_config).with("linkedin").and_return(linkedin_target)
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    it "publishes all generated targets" do
      results = described_class.new(slug, config: config).call
      expect(results.map { |r| r[:target] }).to contain_exactly("tracyatteberry", "linkedin")
    end

    it "updates status to published for each target" do
      described_class.new(slug, config: config).call
      store = Lowmu::ContentStore.new(base_dir)
      expect(store.read_status(slug).dig("tracyatteberry", "status")).to eq("published")
    end

    it "marks LinkedIn as manual with the file path" do
      results = described_class.new(slug, config: config).call
      linkedin_result = results.find { |r| r[:target] == "linkedin" }
      expect(linkedin_result[:status]).to eq(:manual)
      expect(linkedin_result[:file]).to include("linkedin.md")
    end

    it "raises for a target not in generated state" do
      store = Lowmu::ContentStore.new(base_dir)
      store.update_target_status(slug, "tracyatteberry", {"status" => "pending"})
      expect {
        described_class.new(slug, target: "tracyatteberry", config: config).call
      }.to raise_error(Lowmu::Error, /not in.*generated/)
    end

    it "raises if the slug does not exist" do
      expect {
        described_class.new("nonexistent", config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end
  end
end
```

**Step 2: Run to verify failure**

Run: `bundle exec rspec spec/lowmu/commands/publish_spec.rb`
Expected: FAIL

**Step 3: Implement Commands::Publish**

```ruby
# lib/lowmu/commands/publish.rb
module Lowmu
  module Commands
    class Publish
      PUBLISHER_MAP = {
        "hugo" => Publishers::Hugo,
        "substack" => Publishers::Substack,
        "mastodon" => Publishers::Mastodon
      }.freeze

      def initialize(slug, target: nil, config:)
        @slug = slug
        @target_filter = target
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        raise Error, "Slug not found: #{@slug}" unless @store.slug_exists?(@slug)
        resolve_targets.map { |target_name| publish_target(target_name) }
      end

      private

      def publish_target(target_name)
        target_config = @config.target_config(target_name)
        current_status = @store.read_status(@slug).dig(target_name, "status")

        unless current_status == "generated"
          raise Error, "Target '#{target_name}' is not in generated state (current: #{current_status}). Run `lowmu generate` first."
        end

        if target_config["type"] == "linkedin"
          return publish_linkedin(target_name, target_config)
        end

        publisher_class = PUBLISHER_MAP.fetch(target_config["type"]) do
          raise Error, "Unknown target type: #{target_config["type"]}"
        end

        publisher_class.new(@store.slug_dir(@slug), target_config).publish
        @store.update_target_status(@slug, target_name, {
          "status" => "published",
          "published_at" => Time.now.iso8601
        })

        {target: target_name, status: :published}
      end

      def publish_linkedin(target_name, _target_config)
        linkedin_file = File.join(@store.slug_dir(@slug), Generators::Linkedin::OUTPUT_FILE)
        @store.update_target_status(@slug, target_name, {
          "status" => "published",
          "published_at" => Time.now.iso8601,
          "note" => "Manual copy-paste required"
        })
        {target: target_name, status: :manual, file: linkedin_file}
      end

      def resolve_targets
        all_targets = @store.read_status(@slug).keys
        if @target_filter
          raise Error, "Target '#{@target_filter}' not in publish_to list" unless all_targets.include?(@target_filter)
          [@target_filter]
        else
          all_targets
        end
      end
    end
  end
end
```

**Step 4: Run to verify pass**

Run: `bundle exec rspec spec/lowmu/commands/publish_spec.rb`
Expected: All green

**Step 5: Run the full test suite**

Run: `bundle exec rspec`
Expected: All green, coverage >= 90%

**Step 6: Commit**

```bash
git add lib/lowmu/commands/publish.rb spec/lowmu/commands/publish_spec.rb
git commit -m "feat: add Commands::Publish with --target support and LinkedIn manual flow"
```

---

### Task 18: Final Verification

**Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All green, SimpleCov reports >= 90% coverage

**Step 2: Run StandardRB linting**

Run: `bundle exec standardrb`
Expected: No offenses

**Step 3: Smoke test the executable**

Run: `bundle exec lowmu --help`
Expected: Help output listing all commands

Run: `bundle exec lowmu configure --help`
Expected: Help for the configure command

**Step 4: Final commit if needed**

```bash
git add -A
git commit -m "feat: complete lowmu v1 implementation"
```
