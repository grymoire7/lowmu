# Design: ParallelTaskRunner + Generate Progress Feedback

Date: 2026-03-05

## Problem

`lowmu generate SLUG` makes one LLM call per target and produces no output until
all calls complete. On a typical slug with 3-5 targets, this can feel like a
hang of 10-30 seconds with zero feedback.

## Chosen Approach

A zero-coupling `ParallelTaskRunner` utility class runs tasks concurrently,
displaying a multi-line spinner (one per task) via `TTY::Spinner::Multi`. The
CLI builds the task list and owns the UI; `Commands::Generate` stays a pure
data object.

## ParallelTaskRunner

**Location:** `lib/lowmu/parallel_task_runner.rb`

**Interface:**

```ruby
tasks = [
  { opts: { title: "Generating mastodon...", done: "Generated mastodon.md", format: :pulse  }, block: -> { ... } },
  { opts: { title: "Generating linkedin_post...", done: "Generated linkedin_post.md" }, block: -> { ... } },
]

result = ParallelTaskRunner.new(tasks).run
# => { successes: [...block return values...], errors: [...exceptions...] }
```

**Constructor:**

```ruby
def initialize(tasks, tty: $stderr.tty?)
```

`tty:` defaults to `$stderr.tty?` — callers never pass it. Tests pass
`tty: false` to exercise the plain-text path without mocking.

**`opts` keys:** Two lowmu-conventional keys are extracted before the remainder
is forwarded to `TTY::Spinner::Multi#register`:

- `title:` — used as the spinner format string, e.g. `"[:spinner] Generating mastodon..."`
- `done:` — passed to `spinner.success(done)` on success

All other keys (e.g. `format: :pulse`) are forwarded directly to TTY::Spinner,
allowing the full TTY::Spinner option surface. Future keys (e.g. `gerund: true`
for random verbs) can be intercepted the same way.

**Execution:** One thread per task. Each thread calls its block, then calls
`spinner.success(done)` or `spinner.error(e.message)` on the task's spinner.
All threads are joined before `#run` returns.

**Return value:** `{ successes: [return values], errors: [exceptions] }`. The
CLI uses `errors.any?` to set a non-zero exit code.

**Thread safety:** Each task closure captures its own generator instance. Tasks
write to distinct files in the same slug directory. No shared mutable state;
no mutex needed.

## TTY path (default: tty detected)

`TTY::Spinner::Multi` renders a live multi-line display on `$stderr`:

```
[/] Generating mastodon...
[-] Generating linkedin_post...
[|] Generating substack_note...
```

On completion:

```
[+] Generated mastodon.md
[x] linkedin_post: RubyLLM::Error: rate limit exceeded
[+] Generated substack_note.md
```

## Non-TTY path (tty: false)

No TTY::Spinner gem calls. Plain output to `$stderr`:

```
-> Generating mastodon...
-> Generating linkedin_post...
-> Generating substack_note...
✓ Generated mastodon.md
✗ linkedin_post: RubyLLM::Error: rate limit exceeded
✓ Generated substack_note.md
```

This path exists for completeness (piped output, log capture). In practice,
LLM calls are never made in CI, so non-TTY is not a primary concern.

## Error handling

- **Continue-on-error:** all tasks run to completion regardless of individual failures.
- **Inline feedback:** each failing spinner shows `✗ <title>: <error message>`.
- **Exit code:** the CLI exits non-zero if `result[:errors].any?`.
- **Error summary:** after all spinners settle, the CLI prints a summary of
  failed tasks with full error messages for visibility.

## CLI integration

`Commands::Generate` is **unchanged** — it returns
`[{ key:, target:, file: }, ...]` as today.

The CLI's `generate` method:
1. Calls `Commands::Generate#call` to get the item/target list
2. Builds a task array: one entry per `{ key:, target: }` pair, with a block
   that calls the appropriate generator
3. Passes the task array to `ParallelTaskRunner.new(tasks).run`
4. Prints a summary and exits non-zero on any errors

## New dependency

Add `tty-spinner` to `lowmu.gemspec`.

## Testing

- `ParallelTaskRunner` tested in isolation with fast fake blocks (no LLM).
  Tests cover: all-success, partial failure, all-failure, non-TTY path
  (via `tty: false`).
- `Commands::Generate` tests unchanged.
- CLI integration tested by passing `tty: false` and capturing `$stderr`.
