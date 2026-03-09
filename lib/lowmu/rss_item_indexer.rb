require "json"

module Lowmu
  class RssItemIndexer
    PROMPT = <<~PROMPT
      You are analyzing a single article to extract structured metadata for content remixing.
      Read the article below and return a JSON object with exactly these five keys:

        "concept"   – The core subject or topic being explored (one sentence).
        "angle"     – The stance or framing of the piece (one sentence: e.g. "A warning to...", "A beginner's guide to...", "A critique of...").
        "audience"  – Who the piece is written for and what they are assumed to know (one sentence).
        "examples"  – The specific tools, workflows, codebases, or scenarios used (one sentence).
        "conclusion" – What the reader is left thinking or encouraged to do (one sentence).

      Return ONLY the JSON object. No markdown, no commentary.

      <article>
      %{content}
      </article>
    PROMPT

    def initialize(content_dir:, model:, rescan: false)
      @content_dir = File.expand_path(content_dir)
      @index_dir = File.join(@content_dir, "rss", "index")
      @model = model
      @rescan = rescan
      FileUtils.mkdir_p(@index_dir)
    end

    def index(cache_relative_path)
      index_path = index_path_for(cache_relative_path)
      index_full_path = File.join(@content_dir, index_path)

      return index_path if File.exist?(index_full_path) && !@rescan

      cache_content = File.read(File.join(@content_dir, cache_relative_path))
      front_matter = parse_front_matter(cache_content)
      body = cache_content.split(/^---\s*$/, 3).last.to_s.strip

      prompt = PROMPT % {content: "#{front_matter["title"]}\n\n#{body}"}
      raw = RubyLLM.chat(model: @model).ask(prompt).content
      dimensions = JSON.parse(raw)

      data = front_matter.slice("title", "url", "source_name", "fetched_at", "full_content").merge(
        "cache_path" => cache_relative_path,
        "concept" => dimensions["concept"],
        "angle" => dimensions["angle"],
        "audience" => dimensions["audience"],
        "examples" => dimensions["examples"],
        "conclusion" => dimensions["conclusion"]
      )

      File.write(index_full_path, JSON.pretty_generate(data))
      index_path
    end

    private

    def index_path_for(cache_relative_path)
      basename = File.basename(cache_relative_path, ".md")
      File.join("rss", "index", "#{basename}.json")
    end

    def parse_front_matter(content)
      parts = content.split(/^---\s*$/, 3)
      return {} unless parts.length >= 3
      YAML.safe_load(parts[1], permitted_classes: [Date]) || {}
    end
  end
end
