# Brainstorm Progress Callback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single outer spinner in CLI with per-phase progress callbacks injected into `Brainstorm`.

**Architecture:** Add a `with_progress:` kwarg to `Brainstorm#initialize` that defaults to a no-op lambda. `Brainstorm#call` wraps `cache_rss_items`, `index_rss_items`, and `ask_llm` with it. CLI passes `method(:with_spinner)` and removes the outer wrapper.

**Tech Stack:** Ruby, RSpec, TTY::Spinner (already used in CLI)

---

### Task 1: Add `with_progress:` callback to `Brainstorm`

**Files:**
- Modify: `lib/lowmu/commands/brainstorm.rb`
- Test: `spec/lowmu/commands/brainstorm_spec.rb`

**Step 1: Write the failing test**

Add inside `describe "#call"` in `spec/lowmu/commands/brainstorm_spec.rb`:

```ruby
it "invokes with_progress for each phase" do
  messages = []
  progress = ->(msg, &block) { messages << msg; block.call }
  described_class.new(config: config, num: 2, with_progress: progress).call
  expect(messages).to include(
    a_string_matching(/RSS/i),
    a_string_matching(/index/i),
    a_string_matching(/LLM/i)
  )
end
```

**Step 2: Run test to verify it fails**

```bash
bundle exec rspec spec/lowmu/commands/brainstorm_spec.rb --format documentation 2>&1 | tail -20
```

Expected: FAIL with `unknown keyword: with_progress`

**Step 3: Add the constant and kwarg to `Brainstorm`**

In `lib/lowmu/commands/brainstorm.rb`, add the constant just before `def initialize`:

```ruby
NO_OP_PROGRESS = ->(msg, &block) { block.call }
```

Update `initialize` signature:

```ruby
def initialize(config:, form: "long", num: 5, rescan: false, recent: nil, per_source: 3, with_progress: NO_OP_PROGRESS)
  @config = config
  @form = form
  @num = num
  @rescan = rescan
  @recent = recent
  @per_source = per_source
  @with_progress = with_progress
  @state = BrainstormState.new(config.content_dir)
  @writer = IdeaWriter.new(File.join(config.content_dir, "ideas"))
end
```

**Step 4: Wrap the three phases in `call`**

Replace the body of `def call`:

```ruby
def call
  configure_llm
  @with_progress.call("Fetching RSS feeds...") { cache_rss_items }
  @with_progress.call("Indexing items...") { index_rss_items }
  palette = build_palette
  raise Error, "No source items found. Add sources to your config or use --rescan." if palette.empty?

  response = @with_progress.call("Asking LLM...") { ask_llm(build_prompt(palette)) }
  ideas = parse_response(response)
  ideas.map { |idea| @writer.write(**idea) }
end
```

**Step 5: Run the full brainstorm spec to verify all tests pass**

```bash
bundle exec rspec spec/lowmu/commands/brainstorm_spec.rb --format documentation
```

Expected: all green

**Step 6: Commit**

```bash
git add lib/lowmu/commands/brainstorm.rb spec/lowmu/commands/brainstorm_spec.rb
git commit -m "feat: add with_progress callback to Brainstorm"
```

---

### Task 2: Update CLI to inject the progress callback

**Files:**
- Modify: `lib/lowmu/cli.rb`
- Test: `spec/lowmu/cli_spec.rb`

**Step 1: Update the stderr progress test**

The existing test at line 294–299 checks for `/Brainstorming/` on stderr. After this change, there is no outer spinner in CLI — progress messages come from inside `Brainstorm` via the callback. Replace that test with one that verifies CLI passes the callback:

Find and replace this test in `spec/lowmu/cli_spec.rb`:

```ruby
# BEFORE
it "reports progress to stderr while running" do
  allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
    instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md"])
  )
  expect { Lowmu::CLI.start(["brainstorm"]) }.to output(/Brainstorming/).to_stderr
end
```

```ruby
# AFTER
it "passes a with_progress callback to the command" do
  expect(Lowmu::Commands::Brainstorm).to receive(:new).with(
    hash_including(with_progress: instance_of(Method))
  ).and_return(instance_double(Lowmu::Commands::Brainstorm, call: []))
  Lowmu::CLI.start(["brainstorm"])
end
```

**Step 2: Run the CLI spec to verify the test fails**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb --format documentation 2>&1 | tail -20
```

Expected: the new test fails (CLI doesn't pass `with_progress:` yet); existing tests still green

**Step 3: Update `CLI#brainstorm`**

In `lib/lowmu/cli.rb`, replace the `brainstorm` method body:

```ruby
def brainstorm
  command = Commands::Brainstorm.new(
    config: Config.load,
    form: options[:form],
    num: options[:num],
    rescan: options[:rescan],
    recent: options[:recent],
    per_source: options[:per_source],
    with_progress: method(:with_spinner)
  )
  files = command.call
  say "Generated #{files.count} idea#{"s" unless files.count == 1}:"
  files.each { |f| say "  #{f}" }
rescue Lowmu::Error => e
  error_exit(e.message)
end
```

**Step 4: Run the full CLI spec**

```bash
bundle exec rspec spec/lowmu/cli_spec.rb --format documentation
```

Expected: all green

**Step 5: Run the full test suite**

```bash
bundle exec rspec
```

Expected: all green

**Step 6: Commit**

```bash
git add lib/lowmu/cli.rb spec/lowmu/cli_spec.rb
git commit -m "feat: inject with_spinner into Brainstorm as progress callback"
```
