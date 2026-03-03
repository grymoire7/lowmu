# lowmu Redesign Notes

_Brainstormed 2026-03-03. To be turned into an implementation plan after cleanup work is complete._

## Vision

lowmu is a **content preparation tool**, not a publishing tool. Its job is to take
Hugo-ready markdown and produce platform-appropriate versions of that content for
all target channels. The user handles the actual posting.

## Key Changes from v1

### Hugo content directory as source of truth

Instead of `lowmu new` copying files into a separate content store, lowmu scans
the Hugo content directory directly. The user's Hugo project is already the
canonical home for content — no duplication needed.

- `content/posts/` → type: post
- `content/notes/` → type: note
- `type` front-matter field drives generation behavior (already in place)
- `lowmu new` command is removed entirely

### No publishing

Publishing is removed. The `publish_to` front-matter field is no longer needed.
All publisher code (`publishers/`) is deleted. The `lowmu publish` command is
removed.

Generation is the value. The user posts manually from the generated files.

### Generated content location

Generated files live under `.lowmu/generated/SLUG/` at the project root (or
wherever `content_dir` is configured). This keeps Hugo's content directory clean.

`content_dir` defaults to `.lowmu/` and remains configurable.

## Updated Configuration

```yaml
# lowmu configuration file

# Hugo content directory (source of truth for input)
hugo_content_dir: ~/projects/my-blog/content

# Directory where generated content is stored (default: .lowmu/)
content_dir: .lowmu

# LLM configuration
llm:
  provider: anthropic
  model: claude-opus-4-6

# Publishing targets (generation only)
targets:
  - name: my-hugo-blog
    type: hugo
    base_url: https://example.com
    base_path: ~/projects/my-blog/content

  - name: mastodon
    type: mastodon
    base_url: https://mastodon.social

  - name: substack
    type: substack

  - name: linkedin
    type: linkedin
```

Note: LinkedIn and Substack have no auth config since there's no publishing.

## Updated Commands

| Command | v1 | Redesign |
|---|---|---|
| `lowmu configure` | create config file | unchanged |
| `lowmu new` | register a post | **removed** |
| `lowmu generate [SLUG]` | generate for registered slug | scan hugo_content_dir, generate for new/pending content; SLUG optional filter |
| `lowmu status [SLUG]` | show publish status | show generation status across all content |
| `lowmu publish` | publish to targets | **removed** |

## Status Tracking

Status tracks generation state only: `pending` → `generated`.

Stored per-slug in `.lowmu/generated/SLUG/status.yml` (same structure as today,
minus publish-related fields).

`lowmu status` scans `hugo_content_dir`, cross-references `.lowmu/`, and reports
what has and hasn't been generated yet.

## What Stays

- All generators (Hugo, Mastodon, Substack, LinkedIn)
- Note vs post generation logic (being added in cleanup plan)
- Config system
- Status tracking (simplified)
- `FrontMatterParser` usage in generators

## What Goes

- All publishers (`lib/lowmu/publishers/` directory)
- `Commands::Publish`
- `Commands::New`
- `publish_to` front-matter awareness
- Hero image management (was part of `lowmu new`)

## Open Questions

1. Should `lowmu generate` regenerate when the source file changes (mtime-based),
   or only when status is `pending`? `--force` flag handles the explicit case, but
   automatic change detection could be useful.

2. How does `lowmu generate` handle slugs? Options:
   - Derive slug from filename (current behavior via `ContentStore.slug_from_path`)
   - Use a front-matter `slug` field if present, fall back to filename

3. Should `lowmu status` show a diff/summary of what needs generating, like a
   `git status` style output?
