# Status Command Redesign

**Date:** 2026-03-07
**Status:** Approved

## Problem

The current `lowmu status` command reports a single aggregate status per input (`:pending`,
`:stale`, `:generated`, `:ignore`) with no per-target visibility and no filtering options.
The `ignore.yml` file provides a static allowlist workaround but is a poor substitute for
real filtering.

## Goals

- Per-target status visibility in a tabular format
- Robust row-level filtering flags
- Remove `ignore.yml` in favour of date-based `--recent` filtering
- Prevent accidental unbounded `lowmu generate` runs
- Simplify the `targets:` config format

## Approach

Unified per-target status model (Approach B): replace `SlugStatus` with a new `InputStatus`
class that returns per-target statuses as a hash. Both `status` and `generate` draw from this
shared model.

---

## Data Model

### `Lowmu::Generators::REGISTRY`

A shared constant (defined in `lib/lowmu/generators/base.rb`) mapping generator type name
strings to generator classes. Extracted from `Generate::GENERATOR_MAP`.

```ruby
REGISTRY = {
  "substack_long"  => SubstackLong,
  "substack_short" => SubstackShort,
  "mastodon_short" => MastodonShort,
  "linkedin_short" => LinkedinShort,
  "linkedin_long"  => LinkedinLong,
}.freeze
```

### `Lowmu::InputStatus`

Replaces `SlugStatus`. Given a Hugo item and the list of enabled target type names, returns
`{target_type => status_symbol}` for each configured target.

Status symbols:

| Symbol            | Meaning                                                           |
|-------------------|-------------------------------------------------------------------|
| `:done`           | Output file exists and is newer than source                       |
| `:pending`        | Output file does not exist; target is applicable                  |
| `:stale`          | Output file exists but source was modified after it was generated |
| `:not_applicable` | Generator form (:long) is incompatible with content type (:short) |

Also exposes `#aggregate` returning a row-level summary for use by `generate`:

| Value      | Condition                                     |
|------------|-----------------------------------------------|
| `:done`    | All applicable targets are `:done`            |
| `:partial` | Some but not all applicable targets are done  |
| `:pending` | No applicable targets have output             |
| `:stale`   | At least one applicable target is `:stale`    |

### Config `targets:` format (simplified)

The `name`/`type` split is removed. `targets:` is now a flat list of generator type names,
validated against `REGISTRY` at load time.

```yaml
# Before
targets:
  - name: mastodon
    type: mastodon_short
    base_url: https://mastodon.social

# After
targets:
  - mastodon_short
  - substack_long
  - linkedin_short
```

Per-type config (if needed in future) uses a hash entry:

```yaml
targets:
  - mastodon_short:
      base_url: https://mastodon.social
```

---

## `lowmu status` — New Interface

### Options

```
lowmu status [SLUG]
  --all               Default: show all inputs
  --pending           At least one applicable output is pending
  --no-pending        No applicable output is pending
  --recent DURATION   At least one output exists within duration (e.g. 1w, 3d)
  --done              All applicable outputs are done
  --partial           Some but not all applicable outputs are done
  --stale             At least one output is stale
  --no-stale          No output is stale
```

### Tabular output

Rows are inputs (Hugo items). Columns are configured targets. Status indicators:

```
| input         | linkedin/long | linkedin/short | substack/long | substack/short | mastodon/short |
| ------------- | ------------- | -------------- | ------------- | -------------- | -------------- |
| jojo/long     |       ✓       |        ✓       |       ✓       |       ◯        |        ◯       |
| planned/long  |       ◯       |        ◯       |       ◯       |       ◯        |        ◯       |
| codex/short   |       ✗       |        ✓       |       ✗       |       ✓        |        ✓       |
| updated/short |       ✗       |        ⏱       |       ✗       |       ⏱        |        ⏱       |

✓ done  ◯ pending  ✗ not applicable  ⏱ stale
```

Column headers derive from the generator type name: `linkedin_long` → `linkedin/long`.

---

## `lowmu generate` — Changes

### Safety guard

`lowmu generate` without a SLUG or `--recent` flag exits with:

```
Error: Specify a slug or use --recent DURATION to limit scope (e.g. --recent 1w).
```

### New option

```
--recent DURATION   Only generate for inputs with no output within duration (e.g. 1w, 3d)
```

### `--target` help text

Available target types are interpolated from `REGISTRY` so help text is always accurate:

```
-t, [--target=TARGET]  # Target type to generate. Available: substack_long, substack_short, ...
```

### Removed

- `ignore.yml` check (from both `generate` and `status`)
- `GENERATOR_MAP` (replaced by `Generators::REGISTRY`)
- `item_status` / `SlugStatus` usage (replaced by `InputStatus`)

---

## `lowmu configure` — Changes

Wizard writes the simplified `targets:` list format. No migration shim; old configs with
`name`/`type` pairs will raise a `Lowmu::Error` at load time prompting the user to re-run
`lowmu configure`.

---

## Data Flow

### `lowmu status --pending`

```
CLI → Commands::Status
  → HugoScanner#scan                      # all Hugo items
  → InputStatus.new(item, enabled_targets)
      → REGISTRY[type].FORM vs content_type → :not_applicable or check filesystem
      → check OUTPUT_FILE exists in slug_dir
      → compare mtime(source) vs mtime(output) → :done or :stale
  → filter rows where aggregate includes :pending
  → TableRenderer#render                  # ASCII table with ✓ ◯ ✗ ⏱
```

---

## Error Handling

| Scenario                         | Behaviour                                                             |
|----------------------------------|-----------------------------------------------------------------------|
| `generate` with no slug/--recent | Exit with usage hint                                                  |
| Unknown `--target` value         | Exit with `Error: Unknown target type: <value>`                       |
| Invalid `--recent` duration      | Exit with `Error: Invalid duration "x". Use a number followed by d or w.` |
| Unknown type in config targets   | `Config.load` raises `Lowmu::Error` at startup                        |
| Empty targets list in config     | `Config.load` raises `Lowmu::Error` at startup                        |

---

## Testing Plan (TDD)

| Component              | Key cases                                                                        |
|------------------------|----------------------------------------------------------------------------------|
| `Generators::REGISTRY` | All expected keys present; each value responds to `FORM`, `OUTPUT_FILE`          |
| `Config`               | Parses new targets format; rejects unknown type names; raises on empty targets   |
| `InputStatus`          | `:not_applicable` for short+long; `:pending` no output; `:done` newer output; `:stale` older output; `#aggregate` all combinations |
| `DurationParser`       | Parses `1w`, `3d`, `14d`; rejects invalid strings                               |
| `Commands::Status`     | Each filter flag selects correct rows; table output format; legend rendered      |
| `Commands::Generate`   | Guard fires with no slug and no `--recent`; `--recent` limits scope; ignore logic removed |
| `ContentStore`         | `ignore_slugs` and `IGNORE_FILE` absent                                          |

### Deleted tests
- `spec/lowmu/slug_status_spec.rb`
- Ignored-item context in `spec/lowmu/commands/status_spec.rb`

---

## Files Changed

| File | Change |
|------|--------|
| `lib/lowmu/generators/base.rb` | Add `REGISTRY` constant |
| `lib/lowmu/generators/*.rb` | No change (already have `FORM`, `OUTPUT_FILE`) |
| `lib/lowmu/input_status.rb` | New (replaces `slug_status.rb`) |
| `lib/lowmu/duration_parser.rb` | New |
| `lib/lowmu/commands/status.rb` | Rewrite: filters, tabular output |
| `lib/lowmu/commands/generate.rb` | Add guard, `--recent`, use `REGISTRY`/`InputStatus` |
| `lib/lowmu/commands/configure.rb` | Write new targets format |
| `lib/lowmu/config.rb` | Parse new targets format, validate against `REGISTRY` |
| `lib/lowmu/content_store.rb` | Remove `ignore_slugs`, `IGNORE_FILE` |
| `lib/lowmu/cli.rb` | Add status filter options; add `--recent` to generate |
| `lib/lowmu/slug_status.rb` | Delete |
| `spec/lowmu/slug_status_spec.rb` | Delete |
| `spec/lowmu/input_status_spec.rb` | New |
| `spec/lowmu/duration_parser_spec.rb` | New |
| `spec/lowmu/commands/status_spec.rb` | Rewrite |
| `spec/lowmu/commands/generate_spec.rb` | Update |
| `spec/lowmu/config_spec.rb` | Update |
| `spec/lowmu/content_store_spec.rb` | Update |
