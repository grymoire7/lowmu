# Content Type Routing Design

Date: 2026-03-04

## Problem

Three related gaps prevent lowmu from correctly scoping and routing content:

1. `HugoScanner` uses `**/*.md` and scans the entire Hugo content tree, picking up `portfolio/`, `about/`, etc. alongside posts and notes.
2. Scanned items carry no content type — generators cannot distinguish a post from a note.
3. Generators ignore content type, applying all configured targets to every item regardless of form factor. Posts and notes should produce different output sets.

A secondary consequence: if a post and a note share the same slug (e.g. `jojo`), bare-slug identity causes collisions in status output, ignore lists, and the content store.

## Design

### Identity: compound key

The unique identifier throughout the system is `section/slug` (e.g. `posts/jojo`, `notes/jojo`), where `section` is the literal subdirectory name. This acts as a compound key — section and slug together are unique; either alone may not be.

This affects:
- `lowmu status` output: `posts/jojo: generated`
- CLI arguments: `lowmu generate posts/jojo`
- `ignore.yml` entries: `- posts/jojo`
- `ContentStore` paths: `.lowmu/generated/posts/jojo/`

### Config

Two new optional keys with defaults:

```yaml
post_dirs: [posts]   # subdirs of hugo_content_dir treated as long-form input
note_dirs: [notes]   # subdirs of hugo_content_dir treated as short-form input
```

`Config` exposes `post_dirs` and `note_dirs` as arrays of strings. The `hugo` target type is removed.

### HugoScanner

Constructor: `HugoScanner.new(hugo_content_dir, post_dirs:, note_dirs:)`

Scans only the configured dirs (not the full tree). Each item returned:

```ruby
{
  slug: "jojo",
  section: "posts",
  content_type: :post,       # :post or :note
  source_path: "/content/posts/jojo/index.md"
}
```

The compound key `"posts/jojo"` is derived as `"#{section}/#{slug}"` by callers.

### Generator classes

Form factor is a constant on each generator class (`FORM = :long` or `FORM = :short`). Generators no longer read front matter to detect content type internally — it is passed in via the constructor.

| Class | FORM | Output file |
|---|---|---|
| `Generators::SubstackNewsletter` | `:long` | `substack_newsletter.md` |
| `Generators::SubstackNote` | `:short` | `substack_note.md` |
| `Generators::Mastodon` | `:short` | `mastodon.txt` |
| `Generators::LinkedinPost` | `:short` | `linkedin_post.md` |
| `Generators::LinkedinArticle` | `:long` | `linkedin_article.md` |

`Generators::Hugo` is removed. `Generators::Substack` is split into `SubstackNewsletter` and `SubstackNote`. `Generators::Linkedin` is renamed to `LinkedinPost` and `LinkedinArticle` is added.

`GENERATOR_MAP` in `Generate`:

```ruby
{
  "substack_newsletter" => Generators::SubstackNewsletter,
  "substack_note"       => Generators::SubstackNote,
  "mastodon"            => Generators::Mastodon,
  "linkedin_post"       => Generators::LinkedinPost,
  "linkedin_article"    => Generators::LinkedinArticle
}
```

### Generate command

Filters targets by form factor before generating:

```ruby
# Notes skip any target whose generator declares FORM = :long
def applicable_targets(content_type)
  resolve_targets.reject do |target_name|
    content_type == :note &&
      generator_class_for(target_name)::FORM == :long
  end
end
```

All internal references to bare slug are replaced with the compound key.

### Status command

Output format: `posts/jojo: generated`

No other behavioral changes.

## Rule summary

- **Post** (long-form input) → all targets (`:long` and `:short`)
- **Note** (short-form input) → short-form targets only (`:short`)
