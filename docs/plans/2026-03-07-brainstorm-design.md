# Brainstorm Command Design

**Date:** 2026-03-07
**Status:** Approved

## Problem

Lowmu reduces friction for publishing content, but doesn't help with the upstream
problem: generating ideas worth writing about. Reading feeds, taking notes, and
deciding what to write is currently entirely manual.

## Goals

- Scan configured idea sources (RSS feeds, local markdown files) for new material
- Use AI to generate content ideas in the user's voice
- Write ideas as individual markdown files for easy review and selection
- Track which source items have been processed to avoid re-suggesting the same ideas
- Keep scope minimal: brainstorm only, no automated draft promotion

## Non-Goals

- `lowmu draft` command (deferred until brainstorm workflow proves useful)
- Short-form ideas posting directly to social targets (all output feeds into Hugo)
- Automated Hugo draft promotion

## CLI

```
lowmu brainstorm --form=[long|short] --num=N [--rescan]
```

- `--form`: `long` (default) or `short`
- `--num`: number of ideas to generate (default: 5)
- `--rescan`: ignore state, process all available source items (does not clear state)

## Config

New top-level keys in `config.yml`:

```yaml
persona: |
  I write about software engineering, developer tools, and the
  intersection of technology and society. Practical and opinionated.

sources:
  - type: rss
    url: https://feeds.example.com/feed.xml
    name: example-blog
  - type: file
    path: ~/notes/ideas.md
    name: my-ideas
```

`persona` is a freeform text block passed verbatim to the AI as style/audience context.
Each source has a `type` (`rss` or `file`), a `name` (used as the state tracking key),
and either a `url` (RSS) or `path` (file).

## Source Scanning

**RSS:** Fetch the feed, extract items as title + first ~200 words of
description/content. Each item is identified by its `guid` or `link`.

**File:** Read the markdown file and split on `---` or `##` headings, treating each
section as a separate item. Each item is identified by a hash of its heading/first line.

Only title + ~200 words per item are sent to the AI to keep prompts lean.

## State Tracking

State is stored in `.lowmu/brainstorm_state.yml`:

```yaml
sources:
  example-blog:
    last_seen_ids:
      - "https://example.com/post-1"
      - "https://example.com/post-2"
  my-ideas:
    last_seen_ids:
      - "abc123hash"
```

On each run, items whose ID is already in `last_seen_ids` are skipped. After a
successful run, newly processed IDs are added. `--rescan` bypasses the check but
does not modify or clear the state file.

## AI Idea Generation

A single LLM call per run containing:

1. The `persona` from config
2. Pre-processed source items labeled by source name
3. Instruction to generate `--num` ideas mixing angle/take (news-style items) and
   inspired-by (opinion/essay items) as appropriate
4. The desired `--form`

The AI returns structured output (one idea per item) parsed into individual files.
Uses the existing RubyLLM integration.

## Output Files

**Long form** — `$content_dir/ideas/long-{slug}.md`:
```markdown
---
title: "Idea Title"
form: long
source: example-blog
date: 2026-03-07
---

One paragraph summary of the idea and angle.

Potential sections: intro hook, main argument, counterpoint, conclusion.
```

**Short form** — `$content_dir/ideas/short-{slug}.md`:
```markdown
---
title: "Idea Title"
form: short
source: my-ideas
date: 2026-03-07
---

~500 word complete draft ready to review and edit.
```

## Architecture

New files:

```
lib/lowmu/
  commands/brainstorm.rb    # orchestrates the flow
  sources/rss_source.rb     # fetch + parse RSS feeds
  sources/file_source.rb    # read + split local markdown files
  brainstorm_state.rb       # read/write .lowmu/brainstorm_state.yml
  idea_writer.rb            # render idea frontmatter + body to file
```

`Config` gains `#persona` and `#sources` accessors. CLI gains a `brainstorm` Thor command.

**Data flow:**
```
CLI → Commands::Brainstorm
        → Config (persona, sources)
        → BrainstormState (filter seen items)
        → Sources::* (fetch + pre-process items)
        → RubyLLM (generate ideas)
        → IdeaWriter (write idea files)
        → BrainstormState (update seen IDs)
```

**Dependencies:** `rss` (Ruby stdlib) for RSS parsing. No new gems required.

## Testing

- `Commands::Brainstorm` spec uses a VCR cassette for the LLM call
- `Sources::RssSource` spec uses a fixture feed XML file
- `Sources::FileSource`, `BrainstormState`, `IdeaWriter` use unit tests with no network calls
- `Config` spec extended to cover `persona` and `sources` parsing
