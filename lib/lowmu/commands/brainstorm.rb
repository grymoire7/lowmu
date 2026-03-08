module Lowmu
  module Commands
    class Brainstorm
      def initialize(config:, form: "long", num: 5, rescan: false)
        @config = config
        @form = form
        @num = num
        @rescan = rescan
        @state = BrainstormState.new(config.content_dir)
        @writer = IdeaWriter.new(File.join(config.content_dir, "ideas"))
      end

      def call
        configure_llm
        items = gather_items
        raise Error, "No new source items found. Use --rescan to reprocess existing items." if items.empty?

        response = ask_llm(build_prompt(items))
        ideas = parse_response(response)
        files = ideas.map { |idea| @writer.write(**idea) }

        items.group_by { |i| i[:source_name] }.each do |name, source_items|
          @state.mark_seen(name, source_items.map { |i| i[:id] })
        end

        files
      end

      private

      def gather_items
        @config.sources.flat_map do |source|
          all_items = build_source(source).items
          @rescan ? all_items : all_items.reject { |item| @state.seen?(source["name"], item[:id]) }
        end
      end

      def build_source(source)
        case source["type"]
        when "rss" then Sources::RssSource.new(name: source["name"], url: source["url"])
        when "file" then Sources::FileSource.new(name: source["name"], path: source["path"])
        else raise Error, "Unknown source type: #{source["type"]}. Valid types: rss, file"
        end
      end

      def build_prompt(items)
        items_text = items.map { |i| "Source: #{i[:source_name]}\nTitle: #{i[:title]}\n#{i[:excerpt]}" }.join("\n\n---\n\n")
        form_instruction = if @form == "short"
          "Write each idea as a complete ~500 word draft."
        else
          "Write each idea as a one-paragraph summary followed by a list of potential sections."
        end

        <<~PROMPT
          You are a creative content strategist specializing in AI-assisted software development.
          Your job is to generate original article ideas inspired by — but clearly distinct from —
          a set of source articles provided as titles and short excerpts.
          
          You are NOT summarizing or restating these articles. You are remixing them. A good remix
          borrows selectively from multiple sources, never taking too much from any single one.
          
          Each article idea you generate should borrow each of the following elements from a
          DIFFERENT source article:
          
          1. **The concept or topic** — the core subject being explored (eg. cognitive debt,
             context switching, prompt engineering, etc.)
          
          2. **The angle or take** — the stance or framing of the piece. Is it a warning? A
             defense of an unpopular position? A beginner's guide? A critique? A celebration?
          
          3. **The audience and framing** — who the piece is written for and what that reader
             is assumed to already know or care about.
          
          4. **The examples or scenarios** — the specific tools, workflows, codebases, or
             situations used to make the point concrete.
          
          5. **The conclusion or proposed solution** — what the reader is left thinking or
             what they're encouraged to do.
          
          IMPORTANT: If you borrow the concept or topic from a source article, you must take
          the examples, angle, and conclusion from different sources or invent them fresh.
          Never carry over the specific examples, analogies, or proposed solutions from the
          same article you borrowed the topic from. The more distinctive an element is to its
          source (a memorable analogy, a specific tool, a strong opinion), the more important
          it is to leave it behind.
          
          The author's voice and style are fixed and not a variable. Do not borrow or vary
          these. Focus only on what the piece is about, who it's for, how it's framed, and
          how it's structured.
          
          Here is the author persona:
          
              #{@config.persona}
          
          Here are recent articles from a curated feed.
          Each entry includes a title and short excerpt only.
          
          <articles>
              #{items_text}
          </articles>
          
          Before generating ideas, take one unlabeled scratch-pad step: scan the articles and
          note the distinct concepts, angles, audiences, examples, and conclusions you can
          identify. Then use those as your palette.
          
          
          Generate #{@num} original article ideas for #{@form}-form posts.
          For each idea:
          
          - **Pitch:** #{form_instruction}
          - **Audience:** Who is this for and what do they already know?
          - **Format:** What structure will this take? (tutorial, opinion, case study,
            explainer, common-mistakes list, narrative, etc.)
          - **Remix breakdown:** For each of the five elements (concept, angle, audience,
            examples, conclusion), name which source article it came from — or note that it
            was invented fresh. If any two elements point to the same source article, explain
            why that was unavoidable.
          
          Provide exactly #{@num} ideas, each separated by "---".
            
        PROMPT
      end

      def parse_response(response)
        blocks = response.split(/^---$/).map(&:strip).reject(&:empty?)
        blocks.first(@num).filter_map do |block|
          title_match = block.match(/^IDEA:\s*(.+)$/)
          source_match = block.match(/^SOURCE:\s*(.+)$/)
          body_match = block.match(/^BODY:\s*\n(.*)/m)
          next unless title_match && body_match
          {
            title: title_match[1].strip,
            source_name: source_match&.[](1)&.strip || "unknown",
            form: @form,
            body: body_match[1].strip
          }
        end
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
