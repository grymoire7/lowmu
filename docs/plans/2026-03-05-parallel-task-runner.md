# ParallelTaskRunner Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add real-time per-target spinner feedback to `lowmu generate` using a zero-coupling `ParallelTaskRunner` utility.

**Architecture:** A new `ParallelTaskRunner` class runs tasks concurrently (one thread each), displaying a live multi-line TTY::Spinner::Multi display on stderr. `Commands::Generate` is refactored to expose a `#plan` method (returning generator instances without executing them); the CLI builds tasks from the plan and hands them to the runner. `Commands::Generate#call` is preserved for backwards-compatibility.

**Tech Stack:** Ruby threads, TTY::Spinner::Multi (`tty-spinner` gem), RSpec instance_doubles for spinner testing.

---

### Task 1: Add tty-spinner gem dependency

**Files:**
- Modify: `lowmu.gemspec`

**Step 1: Add the dependency**

In `lowmu.gemspec`, add after the existing `add_dependency` lines:

```ruby
spec.add_dependency "tty-spinner", "~> 0.9"
```

**Step 2: Install the gem**

```bash
bundle install
```

**Step 3: Verify existing tests still pass**

```bash
bundle exec rspec
```

Expected: all green.

**Step 4: Commit**

```bash
git add lowmu.gemspec Gemfile.lock
git commit -m "chore: add tty-spinner dependency"
```

---

### Task 2: ParallelTaskRunner — non-TTY path

**Files:**
- Create: `spec/lowmu/parallel_task_runner_spec.rb`
- Create: `lib/lowmu/parallel_task_runner.rb`

**Step 1: Write the failing tests**

Create `spec/lowmu/parallel_task_runner_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Lowmu::ParallelTaskRunner do
  let(:output) { StringIO.new }

  def runner(tasks)
    described_class.new(tasks, tty: false, output: output)
  end

  describe "#run" do
    context "when all tasks succeed" do
      let(:tasks) do
        [
          {opts: {title: "Task A", done: "Done A"}, block: -> { "result_a" }},
          {opts: {title: "Task B", done: "Done B"}, block: -> { "result_b" }}
        ]
      end

      it "returns successes with block return values" do
        result = runner(tasks).run
        expect(result.successes.map(&:value)).to contain_exactly("result_a", "result_b")
      end

      it "returns no errors" do
        result = runner(tasks).run
        expect(result.errors).to be_empty
      end

      it "prints start and done messages to output" do
        runner(tasks).run
        expect(output.string).to include("-> Task A")
        expect(output.string).to include("✓ Done A")
      end
    end

    context "when one task fails" do
      let(:tasks) do
        [
          {opts: {title: "Good", done: "Done"}, block: -> { "ok" }},
          {opts: {title: "Bad", done: "Done"}, block: -> { raise "boom" }}
        ]
      end

      it "continues other tasks and captures the error" do
        result = runner(tasks).run
        expect(result.successes.size).to eq(1)
        expect(result.errors.size).to eq(1)
      end

      it "captures the exception" do
        result = runner(tasks).run
        expect(result.errors.first.exception.message).to eq("boom")
      end

      it "includes the title in the error" do
        result = runner(tasks).run
        expect(result.errors.first.title).to eq("Bad")
      end

      it "prints the error inline" do
        runner(tasks).run
        expect(output.string).to include("✗ Bad: boom")
      end
    end

    context "when all tasks fail" do
      let(:tasks) do
        [
          {opts: {title: "A", done: "done"}, block: -> { raise "err1" }},
          {opts: {title: "B", done: "done"}, block: -> { raise "err2" }}
        ]
      end

      it "returns empty successes" do
        expect(runner(tasks).run.successes).to be_empty
      end

      it "returns all errors" do
        expect(runner(tasks).run.errors.size).to eq(2)
      end
    end
  end
end
```

**Step 2: Run tests to confirm they fail**

```bash
bundle exec rspec spec/lowmu/parallel_task_runner_spec.rb
```

Expected: `NameError: uninitialized constant Lowmu::ParallelTaskRunner`

**Step 3: Implement ParallelTaskRunner with non-TTY path**

Create `lib/lowmu/parallel_task_runner.rb`:

```ruby
module Lowmu
  class ParallelTaskRunner
    Result = Struct.new(:successes, :errors, keyword_init: true)
    TaskSuccess = Struct.new(:title, :value, keyword_init: true)
    TaskError = Struct.new(:title, :exception, keyword_init: true)

    def initialize(tasks, tty: $stderr.tty?, output: $stderr)
      @tasks = tasks
      @tty = tty
      @output = output
    end

    def run
      if @tty
        run_with_spinners
      else
        run_plain
      end
    end

    private

    def run_plain
      successes = []
      errors = []
      mutex = Mutex.new

      threads = @tasks.map do |task|
        opts = task[:opts].dup
        title = opts.delete(:title) || "Running..."
        done = opts.delete(:done) || "Done"
        block = task[:block]

        @output.puts "-> #{title}"

        Thread.new do
          begin
            value = block.call
            mutex.synchronize do
              @output.puts "✓ #{done}"
              successes << TaskSuccess.new(title: title, value: value)
            end
          rescue => e
            mutex.synchronize do
              @output.puts "✗ #{title}: #{e.message}"
              errors << TaskError.new(title: title, exception: e)
            end
          end
        end
      end

      threads.each(&:join)
      Result.new(successes: successes, errors: errors)
    end

    def run_with_spinners
      # implemented in Task 3
      raise NotImplementedError
    end
  end
end
```

**Step 4: Run tests to confirm they pass**

```bash
bundle exec rspec spec/lowmu/parallel_task_runner_spec.rb
```

Expected: all green.

**Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green (coverage may warn — will be resolved in later tasks).

**Step 6: Commit**

```bash
git add lib/lowmu/parallel_task_runner.rb spec/lowmu/parallel_task_runner_spec.rb
git commit -m "feat: add ParallelTaskRunner with non-TTY path"
```

---

### Task 3: ParallelTaskRunner — TTY spinner path

**Files:**
- Modify: `spec/lowmu/parallel_task_runner_spec.rb`
- Modify: `lib/lowmu/parallel_task_runner.rb`

The TTY path uses `TTY::Spinner::Multi`. We test it by stubbing the spinner classes
with instance_doubles — this avoids terminal interaction in tests while still verifying
that the right methods are called.

**Step 1: Write the failing TTY tests**

Add a new context to `spec/lowmu/parallel_task_runner_spec.rb`, inside `describe "#run"`:

```ruby
context "when tty: true" do
  let(:spinner) { instance_double(TTY::Spinner, auto_spin: nil, success: nil, error: nil) }
  let(:multi) { instance_double(TTY::Spinner::Multi) }

  before do
    allow(TTY::Spinner::Multi).to receive(:new).and_return(multi)
    allow(multi).to receive(:register).and_return(spinner)
  end

  def tty_runner(tasks)
    described_class.new(tasks, tty: true)
  end

  context "when a task succeeds" do
    let(:tasks) do
      [{opts: {title: "Task A", done: "Done A", format: :pulse}, block: -> { "x" }}]
    end

    it "returns the result as a success" do
      result = tty_runner(tasks).run
      expect(result.successes.first.value).to eq("x")
    end

    it "calls auto_spin on the spinner" do
      tty_runner(tasks).run
      expect(spinner).to have_received(:auto_spin)
    end

    it "calls success with the done message" do
      tty_runner(tasks).run
      expect(spinner).to have_received(:success).with("Done A")
    end

    it "registers the spinner with the title and extra opts" do
      tty_runner(tasks).run
      expect(multi).to have_received(:register).with("[:spinner] Task A", format: :pulse)
    end
  end

  context "when a task fails" do
    let(:tasks) do
      [{opts: {title: "Bad", done: "Done"}, block: -> { raise "boom" }}]
    end

    it "captures the error" do
      result = tty_runner(tasks).run
      expect(result.errors.first.exception.message).to eq("boom")
    end

    it "calls error with the exception message" do
      tty_runner(tasks).run
      expect(spinner).to have_received(:error).with("boom")
    end
  end
end
```

**Step 2: Run tests to confirm they fail**

```bash
bundle exec rspec spec/lowmu/parallel_task_runner_spec.rb
```

Expected: failures on the TTY context (`NotImplementedError` from `run_with_spinners`).

**Step 3: Implement run_with_spinners**

Replace the `run_with_spinners` stub in `lib/lowmu/parallel_task_runner.rb`:

```ruby
def run_with_spinners
  require "tty-spinner"
  successes = []
  errors = []
  mutex = Mutex.new

  multi = TTY::Spinner::Multi.new(output: @output)

  spinner_tasks = @tasks.map do |task|
    opts = task[:opts].dup
    title = opts.delete(:title) || "Running..."
    done = opts.delete(:done) || "Done"
    sp = multi.register("[:spinner] #{title}", **opts)
    [sp, title, done, task[:block]]
  end

  threads = spinner_tasks.map do |sp, title, done, block|
    Thread.new do
      sp.auto_spin
      begin
        value = block.call
        sp.success(done)
        mutex.synchronize { successes << TaskSuccess.new(title: title, value: value) }
      rescue => e
        sp.error(e.message)
        mutex.synchronize { errors << TaskError.new(title: title, exception: e) }
      end
    end
  end

  threads.each(&:join)
  Result.new(successes: successes, errors: errors)
end
```

Note: `TTY::Spinner::Multi.new` accepts `output:` for directing spinner output, used in tests.

**Step 4: Run the TTY tests**

```bash
bundle exec rspec spec/lowmu/parallel_task_runner_spec.rb
```

Expected: all green.

**Step 5: Run full suite**

```bash
bundle exec rspec
```

Expected: all green.

**Step 6: Commit**

```bash
git add lib/lowmu/parallel_task_runner.rb spec/lowmu/parallel_task_runner_spec.rb
git commit -m "feat: add TTY spinner path to ParallelTaskRunner"
```

---

### Task 4: Refactor Commands::Generate to expose #plan

**Files:**
- Modify: `lib/lowmu/commands/generate.rb`
- Modify: `spec/lowmu/commands/generate_spec.rb`

`#plan` returns `[{ key:, target:, generator: }]` without running generators.
`#call` is refactored to use `#plan` — all existing tests continue to pass.

**Step 1: Verify existing tests pass before touching anything**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb
```

Expected: all green.

**Step 2: Write a failing test for #plan**

Add a new `describe "#plan"` block to `spec/lowmu/commands/generate_spec.rb`,
after the existing `describe "#call"` block:

```ruby
describe "#plan" do
  context "with a pending post" do
    it "returns one entry per applicable target" do
      results = described_class.new(config: config).plan
      expect(results.map { |r| r[:target] }).to contain_exactly("mastodon", "substack-newsletter")
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
```

**Step 3: Run to confirm failures**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb -e "plan"
```

Expected: `NoMethodError: undefined method 'plan'`

**Step 4: Refactor generate.rb**

Replace the contents of `lib/lowmu/commands/generate.rb`:

```ruby
module Lowmu
  module Commands
    class Generate
      GENERATOR_MAP = {
        "substack_newsletter" => Generators::SubstackNewsletter,
        "substack_note" => Generators::SubstackNote,
        "mastodon" => Generators::Mastodon,
        "linkedin_post" => Generators::LinkedinPost,
        "linkedin_article" => Generators::LinkedinArticle
      }.freeze

      def initialize(key_filter = nil, config:, target: nil, force: false)
        @key_filter = key_filter
        @target_filter = target
        @force = force
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def plan
        configure_llm
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter
        warn_stale(items)
        items.select { |item| should_generate?(item) }
          .flat_map { |item| plan_item(item) }
      end

      def call
        plan.map do |t|
          file = t[:generator].generate
          {key: t[:key], target: t[:target], file: file}
        end
      end

      private

      def plan_item(item)
        @store.ensure_slug_dir(item[:key])
        applicable_targets(item[:content_type]).map do |target_name|
          target_config = @config.target_config(target_name)
          generator_class = generator_class_for(target_name)
          generator = generator_class.new(
            @store.slug_dir(item[:key]),
            item[:source_path],
            item[:content_type],
            target_config,
            @config.llm
          )
          {key: item[:key], target: target_name, generator: generator}
        end
      end

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

**Step 5: Run all generate tests**

```bash
bundle exec rspec spec/lowmu/commands/generate_spec.rb
```

Expected: all green (both `#call` and `#plan` contexts).

**Step 6: Run full suite**

```bash
bundle exec rspec
```

Expected: all green.

**Step 7: Commit**

```bash
git add lib/lowmu/commands/generate.rb spec/lowmu/commands/generate_spec.rb
git commit -m "feat: expose Commands::Generate#plan for parallel execution"
```

---

### Task 5: CLI integration

**Files:**
- Modify: `lib/lowmu/cli.rb`
- Modify: `spec/lowmu/cli_spec.rb`

The CLI `generate` method calls `command.plan`, builds `ParallelTaskRunner` tasks,
runs them, and exits non-zero on any errors.

**Step 1: Verify existing CLI tests pass**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb
```

Expected: all green (they currently stub `command.call`).

**Step 2: Update the CLI generate tests**

Replace the entire `describe "#generate"` block in `spec/lowmu/cli_spec.rb`:

```ruby
describe "#generate" do
  let(:command) { instance_double(Lowmu::Commands::Generate) }
  let(:config) { instance_double(Lowmu::Config) }
  let(:runner) { instance_double(Lowmu::ParallelTaskRunner) }

  before do
    allow(Lowmu::Config).to receive(:load).and_return(config)
    allow(Lowmu::Commands::Generate).to receive(:new).and_return(command)
    allow(Lowmu::ParallelTaskRunner).to receive(:new).and_return(runner)
  end

  context "when there is nothing to generate and no slug is given" do
    before { allow(command).to receive(:plan).and_return([]) }

    it "says nothing to generate" do
      expect { cli.generate }.to output(/Nothing to generate/).to_stdout
    end
  end

  context "when there is nothing to generate and a slug is given" do
    before { allow(command).to receive(:plan).and_return([]) }

    it "produces no output" do
      expect { cli.generate("my-post") }.not_to output.to_stdout
    end
  end

  context "when content is generated successfully" do
    let(:generator_a) { instance_double(Lowmu::Generators::Mastodon) }
    let(:planned) do
      [{key: "posts/my-post", target: "mastodon", generator: generator_a}]
    end
    let(:success) { Lowmu::ParallelTaskRunner::TaskSuccess.new(title: "Generating mastodon...", value: "/tmp/mastodon.txt") }
    let(:run_result) { Lowmu::ParallelTaskRunner::Result.new(successes: [success], errors: []) }

    before do
      allow(command).to receive(:plan).and_return(planned)
      allow(runner).to receive(:run).and_return(run_result)
    end

    it "does not print to stdout" do
      expect { cli.generate }.not_to output.to_stdout
    end

    it "builds a runner with one task per planned item" do
      cli.generate
      expect(Lowmu::ParallelTaskRunner).to have_received(:new).with(
        [hash_including(opts: hash_including(title: /mastodon/, done: /mastodon/))],
        no_args
      )
    end
  end

  context "when some tasks fail" do
    let(:error) { Lowmu::ParallelTaskRunner::TaskError.new(title: "Generating mastodon...", exception: RuntimeError.new("rate limit")) }
    let(:run_result) { Lowmu::ParallelTaskRunner::Result.new(successes: [], errors: [error]) }
    let(:planned) do
      [{key: "posts/my-post", target: "mastodon", generator: instance_double(Lowmu::Generators::Mastodon)}]
    end

    before do
      allow(command).to receive(:plan).and_return(planned)
      allow(runner).to receive(:run).and_return(run_result)
      allow(cli).to receive(:exit)
    end

    it "prints error details to stdout" do
      expect { cli.generate }.to output(/rate limit/).to_stdout
    end

    it "exits with code 1" do
      cli.generate
      expect(cli).to have_received(:exit).with(1)
    end
  end

  context "when Lowmu::Error is raised" do
    before do
      allow(command).to receive(:plan).and_raise(Lowmu::Error, "no config")
      allow(cli).to receive(:exit)
    end

    it "prints an error message and exits with code 1" do
      expect { cli.generate }.to output(/Error: no config/).to_stdout
      expect(cli).to have_received(:exit).with(1)
    end
  end
end
```

**Step 3: Run to confirm failures**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb -e "generate"
```

Expected: failures (CLI still calls `command.call`).

**Step 4: Update the CLI generate method**

Replace the `generate` method in `lib/lowmu/cli.rb` (lines 22–36):

```ruby
def generate(slug = nil)
  command = Commands::Generate.new(
    slug,
    target: options[:target],
    force: options[:force],
    config: Config.load
  )

  planned = command.plan

  if planned.empty?
    say "Nothing to generate." unless slug
    return
  end

  tasks = planned.map do |t|
    {
      opts: {
        title: "Generating #{t[:target]} for #{t[:key]}...",
        done: "Generated #{t[:target]} for #{t[:key]}"
      },
      block: -> { t[:generator].generate }
    }
  end

  result = ParallelTaskRunner.new(tasks).run

  if result.errors.any?
    say "\nErrors:", :red
    result.errors.each { |e| say "  #{e.title}: #{e.exception.message}", :red }
    exit(1)
  end
rescue Lowmu::Error => e
  error_exit(e.message)
end
```

**Step 5: Run CLI tests**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb
```

Expected: all green.

**Step 6: Run full suite with coverage**

```bash
bundle exec rspec
```

Expected: all green, coverage >= 90%.

**Step 7: Commit**

```bash
git add lib/lowmu/cli.rb spec/lowmu/cli_spec.rb
git commit -m "feat: use ParallelTaskRunner in generate command for live spinner feedback"
```
