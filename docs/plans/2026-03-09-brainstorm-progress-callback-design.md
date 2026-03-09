# Design: Brainstorm Progress Callback

## Problem

`Brainstorm.call` has multiple slow phases (RSS fetching, indexing, LLM call). A single spinner in CLI wrapping the whole operation gives poor feedback. Finer-grained spinners require moving spinner logic closer to where work happens — but we don't want to mix UI concerns into the business logic layer.

## Approach

Inject a `with_progress:` callable into `Brainstorm`. The callable wraps a named step and returns the block's result. A no-op default keeps the interface backward-compatible and tests unchanged.

## Design

### Interface

```ruby
with_progress = ->(message, &block) { block.call }  # no-op default

Brainstorm.new(config: config, with_progress: with_progress)
```

### `Brainstorm` changes

- Add `with_progress:` kwarg to `initialize`, defaulting to `NO_OP_PROGRESS`
- Wrap `cache_rss_items`, `index_rss_items`, and `ask_llm` in `@with_progress.call("...") { ... }`

### `CLI` changes

- Pass `with_progress: method(:with_spinner)` when constructing `Brainstorm`
- Remove the outer `with_spinner` wrapper around `command.call`

### Data flow

```
CLI#brainstorm
  → Brainstorm.new(with_progress: method(:with_spinner))
  → command.call
      → @with_progress.call("Fetching RSS feeds...")  { cache_rss_items }
      → @with_progress.call("Indexing items...")      { index_rss_items }
      → @with_progress.call("Asking LLM...")          { ask_llm(...) }
```

## Trade-offs

- `Brainstorm` stays UI-agnostic and fully testable without any spinner setup
- CLI retains full control over how progress is rendered
- Slightly more wiring in CLI (one extra kwarg)

## Out of scope

- Extracting `with_spinner` to a shared module (unnecessary at two call sites)
- A `Progress` object/interface (overkill for current scale)
