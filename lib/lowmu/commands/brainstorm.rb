require "json"

module Lowmu
  module Commands
    class Brainstorm
      def initialize(config:, form: "long", num: 5, rescan: false, recent: nil, per_source: 3)
        @config = config
        @form = form
        @num = num
        @rescan = rescan
        @recent = recent
        @per_source = per_source
        @state = BrainstormState.new(config.content_dir)
        @writer = IdeaWriter.new(File.join(config.content_dir, "ideas"))
      end

      def call
        configure_llm
        cache_rss_items
        index_rss_items
        palette = build_palette
        raise Error, "No source items found. Add sources to your config or use --rescan." if palette.empty?

        response = ask_llm(build_prompt(palette))
        ideas = parse_response(response)
        ideas.map { |idea| @writer.write(**idea) }
      end

      private

      # Phase 1: fetch and cache new RSS items
      def cache_rss_items
        rss_sources.each do |source|
          cache = RssItemCache.new(@config.content_dir)
          build_rss_source(source).items.each do |item|
            next if !@rescan && @state.cached?(source["name"], item[:id])

            path = cache.write(item)
            @state.mark_cached(source["name"], item[:id], path)
          end
        end
      end

      # Phase 2: index any cache files that lack a corresponding index file
      def index_rss_items
        indexer = RssItemIndexer.new(
          content_dir: @config.content_dir,
          model: @config.index_model,
          rescan: @rescan
        )
        cache_dir = File.join(@config.content_dir, "rss", "cache")
        return unless Dir.exist?(cache_dir)

        Dir.glob("#{cache_dir}/*.md").each do |full_path|
          relative = full_path.delete_prefix("#{File.expand_path(@config.content_dir)}/")
          indexer.index(relative)
        end
      end

      # Phase 3a: build the palette from index files + file sources
      def build_palette
        rss_items = load_index_items
        file_items = load_file_items
        rss_items + file_items
      end

      def load_index_items
        index_dir = File.join(@config.content_dir, "rss", "index")
        return [] unless Dir.exist?(index_dir)

        all = Dir.glob("#{index_dir}/*.json").filter_map do |path|
          JSON.parse(File.read(path))
        rescue JSON::ParserError
          nil
        end

        all = filter_by_recent(all) if @recent

        by_source = all.group_by { |item| item["source_name"] }
        by_source.flat_map { |_, items| items.first(@per_source) }
      end

      def filter_by_recent(items)
        cutoff = Date.today - (DurationParser.parse(@recent) / 86_400)
        items.select do |item|
          fetched = Date.parse(item["fetched_at"].to_s)
          fetched && fetched >= cutoff
        rescue Date::Error
          false
        end
      end

      def load_file_items
        file_sources.flat_map do |source|
          build_file_source(source).items
        end
      end

      def build_prompt(palette)
        items_text = palette.map { |item| format_palette_item(item) }.join("\n\n---\n\n")
        form_instruction = (@form == "short") ?
          "Write each idea as a complete ~500 word draft." :
          "Write each idea as a one-paragraph summary followed by a list of potential sections."

        <<~PROMPT
          You are a creative content strategist specializing in AI-assisted software development.
          Your job is to generate original article ideas inspired by — but clearly distinct from —
          a set of source articles provided as structured metadata.

          You are NOT summarizing or restating these articles. You are remixing them.

          Each article idea you generate should borrow each of the following elements from a
          DIFFERENT source article:

          1. **The concept or topic**
          2. **The angle or take**
          3. **The audience and framing**
          4. **The examples or scenarios**
          5. **The conclusion or proposed solution**

          Here is the author persona:

              #{@config.persona}

          Here are recent articles from a curated feed, each pre-analyzed for remix dimensions:

          <articles>
              #{items_text}
          </articles>

          Generate #{@num} original article ideas for #{@form}-form posts.
          For each idea:

          - **Pitch:** #{form_instruction}
          - **Audience:** Who is this for and what do they already know?
          - **Format:** What structure will this take?
          - **Remix breakdown:** For each of the five elements, name which source article it came
            from (use the title) — or note it was invented fresh.

          Format your response for each idea exactly as follows:

            TITLE: A one-line title for the idea
            CONCEPT_SOURCE: Title of source article (or "fresh")
            ANGLE_SOURCE: Title of source article (or "fresh")
            AUDIENCE_SOURCE: Title of source article (or "fresh")
            EXAMPLES_SOURCE: Title of source article (or "fresh")
            CONCLUSION_SOURCE: Title of source article (or "fresh")
            BODY: A detailed description of the idea. Several paragraphs.

          Provide exactly #{@num} ideas, each separated by "---".
        PROMPT
      end

      def format_palette_item(item)
        if item.is_a?(Hash) && item.key?("concept")
          "Title: #{item["title"]}\nSource: #{item["source_name"]}\n" \
            "Concept: #{item["concept"]}\nAngle: #{item["angle"]}\n" \
            "Audience: #{item["audience"]}\nExamples: #{item["examples"]}\n" \
            "Conclusion: #{item["conclusion"]}"
        else
          "Source: #{item[:source_name]}\nTitle: #{item[:title]}\n#{item[:excerpt]}"
        end
      end

      def parse_response(response)
        blocks = response.split(/^---$/).map(&:strip).reject(&:empty?)
        blocks.first(@num).filter_map do |block|
          title_match = block.match(/^TITLE:\s*(.+)$/)
          concept_match = block.match(/^CONCEPT_SOURCE:\s*(.+)$/)
          angle_match = block.match(/^ANGLE_SOURCE:\s*(.+)$/)
          audience_match = block.match(/^AUDIENCE_SOURCE:\s*(.+)$/)
          examples_match = block.match(/^EXAMPLES_SOURCE:\s*(.+)$/)
          conclusion_match = block.match(/^CONCLUSION_SOURCE:\s*(.+)$/)
          body_match = block.match(/^BODY:\s*\n(.*)/m)
          next unless title_match && body_match
          {
            title: title_match[1].strip,
            concept_source: concept_match&.[](1)&.strip || "unknown",
            angle_source: angle_match&.[](1)&.strip || "unknown",
            audience_source: audience_match&.[](1)&.strip || "unknown",
            examples_source: examples_match&.[](1)&.strip || "unknown",
            conclusion_source: conclusion_match&.[](1)&.strip || "unknown",
            form: @form,
            body: body_match[1].strip
          }
        end
      end

      def rss_sources
        @config.sources.select { |s| s["type"] == "rss" }
      end

      def file_sources
        @config.sources.select { |s| s["type"] == "file" }
      end

      def build_rss_source(source)
        Sources::RssSource.new(name: source["name"], url: source["url"])
      end

      def build_file_source(source)
        Sources::FileSource.new(name: source["name"], path: source["path"])
      end

      def ask_llm(prompt)
        model = @config.llm.fetch("model") do
          raise Error, "No model configured. Run `lowmu configure` to set up an LLM provider."
        end
        RubyLLM.chat(model: model).ask(prompt).content
      rescue RubyLLM::ConfigurationError
        raise Error, "ANTHROPIC_API_KEY is not set. Please set it in your environment before running lowmu."
      end

      def configure_llm
        RubyLLM.configure do |c|
          c.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
        end
      end
    end
  end
end
