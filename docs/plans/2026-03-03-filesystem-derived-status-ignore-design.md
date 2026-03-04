# Design: Filesystem-derived status + ignore file

Date: 2026-03-03

## Problem

Running `lowmu status` shows all posts as `pending` because no `status.yml` exists until
`lowmu generate` is run. Users with a large backlog of posts don't want to generate content
for all of them — they need a way to mark posts as ignored before running generate.

## Key insight

Status (`pending`, `generated`, `stale`) is fully derivable from the filesystem:
- Whether `generated/<slug>/` exists and contains files → pending or not
- Source file mtime vs. oldest generated file mtime → generated or stale

There is no useful caching possible — status must always be recomputed from live filesystem
state. The only truly persistent state is user intent: which slugs to ignore.

## Design

### Status computation

`SlugStatus` always computes status fresh from the filesystem:

1. Check the ignore list — if slug is present, return `:ignore`
2. Check `generated/<slug>/` — if absent or empty, return `:pending`
3. Compare source file mtime against the oldest mtime among all files in `generated/<slug>/`:
   - Source newer → `:stale`
   - Otherwise → `:generated`

### Ignore file

Location: `<lowmu_content_dir>/ignore.yml`

A simple YAML list of slugs, edited directly by the user:

```yaml
- my-old-post
- another-backlog-post
```

If the file does not exist, no slugs are ignored. `SlugStatus` reads this file on each call.

### ContentStore changes

Remove:
- `write_status` — nothing writes status metadata anymore
- `read_status` — no per-slug status.yml to read
- `generated_at` — derived from file mtimes instead

Keep:
- `slug_dir`, `slug_exists?`, `ensure_slug_dir`, `slugs` — still needed for generated output dirs

Add:
- `ignore_slugs` — reads `ignore.yml`, returns array of slugs (empty array if file absent)

### Commands::Generate changes

Remove the `@store.write_status(...)` call after generating. Generated files land in
`generated/<slug>/` and their mtimes serve as the implicit record of when generation occurred.
`SlugStatus` checks for `:ignore` and skips those slugs.

### What stays the same

`HugoScanner`, `Commands::Status`, `Commands::Generate` (structure), all generators —
no significant changes beyond the `ContentStore` and `SlugStatus` updates.

## File structure

```
<lowmu_content_dir>/
  ignore.yml            # user-edited ignore list (new)
  generated/
    <slug>/             # output files only, no status.yml
      hugo.md
      mastodon.txt
      ...
```
