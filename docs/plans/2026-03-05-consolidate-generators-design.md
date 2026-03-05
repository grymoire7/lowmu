# Design: Consolidate and Standardize Generators

Date: 2026-03-05

## Problem

The generator layer has two related issues:

1. **Inconsistent terminology.** Input content types are named `:post` and `:note` (from Hugo
   conventions), while generator `FORM` values already use `:long` and `:short`. This mismatch
   makes the code harder to follow.

2. **Confusing generator split.** LinkedIn has two generators (`LinkedinPost`, `LinkedinArticle`)
   named after output format but not consistently — a "post" can be either short or long depending
   on context. Similarly, Substack has `SubstackNewsletter` and `SubstackNote`. The naming does not
   clearly express what each generator produces.

## Decision

Standardize on `:long` / `:short` everywhere, and rename all generators and output files to
reflect the output type explicitly.

## Terminology

| Old | New |
|-----|-----|
| `:post` (content_type) | `:long` |
| `:note` (content_type) | `:short` |
| `FORM = :long` | `FORM = :long` (no change) |
| `FORM = :short` | `FORM = :short` (no change) |

`HugoScanner` maps `post_dirs` → `:long`, `note_dirs` → `:short`. All downstream code uses
`:long` / `:short`.

## Generators

Five generators, one per distinct output type:

| Class | `FORM` | `:long` input | `:short` input |
|-------|--------|---------------|----------------|
| `LinkedinLong` | `:long` | LLM (tone) | N/A — filtered out |
| `LinkedinShort` | `:short` | LLM (length + tone) | LLM (tone only) |
| `SubstackLong` | `:long` | strip front matter, copy | N/A — filtered out |
| `SubstackShort` | `:short` | LLM (length) | strip front matter, copy |
| `MastodonShort` | `:short` | LLM (length) | strip front matter, copy |

Generators with `FORM = :long` are excluded from `:short` input by `applicable_targets` in
`generate.rb` — no internal branching needed for N/A cases.

### Renames

| Old class | New class | Old output file | New output file |
|-----------|-----------|-----------------|-----------------|
| `LinkedinArticle` | `LinkedinLong` | `linkedin_article.md` | `linkedin_long.md` |
| `LinkedinPost` | `LinkedinShort` | `linkedin_post.md` | `linkedin_short.md` |
| `SubstackNewsletter` | `SubstackLong` | `substack_newsletter.md` | `substack_long.md` |
| `SubstackNote` | `SubstackShort` | `substack_note.md` | `substack_short.md` |
| `Mastodon` | `MastodonShort` | (unchanged) | `mastodon_short.md` |

`GENERATOR_MAP` keys in `generate.rb`: `"linkedin_long"`, `"linkedin_short"`, `"substack_long"`,
`"substack_short"`, `"mastodon_short"`.

## Directory Structure

Slug directories are nested under content type:

```
.lowmu/
├── long/
│   └── SLUG/
│       ├── linkedin_long.md
│       ├── linkedin_short.md
│       ├── substack_long.md
│       ├── substack_short.md
│       └── mastodon_short.md
└── short/
    └── SLUG/
        ├── linkedin_short.md
        ├── substack_short.md
        └── mastodon_short.md
```

`ContentStore` incorporates `content_type` (`:long` / `:short`) when building slug paths.

## Config

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
```

Both `default_config.yml` (template) and `sample_config.yml` (test fixture) updated.

## Testing

Existing specs updated in place — no new test strategy required:

- `linkedin_article_spec.rb` → `linkedin_long_spec.rb`
- `linkedin_post_spec.rb` → `linkedin_short_spec.rb`
- `substack_newsletter_spec.rb` → `substack_long_spec.rb`
- `substack_note_spec.rb` → `substack_short_spec.rb`
- `mastodon_spec.rb` — updated for new symbols and output filename
- `generate_spec.rb` — updated for new `GENERATOR_MAP` keys, symbols, slug paths
- `content_store_spec.rb` (if exists) — updated for new path structure

All existing test cases survive; changes are vocabulary only.

## Out of Scope

- No changes to prompt content
- No changes to LLM integration
- No changes to `HugoScanner` logic beyond the content type symbol rename
