module Lowmu
  module Commands
    class Brainstorm
      def initialize(config:, form: "long", num: 5, rescan: false)
        @config = config
        @form = form
        @num = num
        @rescan = rescan
        @state = BrainstormState.new(config.content_dir)
        @writer = IdeaWriter.new(File.join(config.hugo_content_dir, "ideas"))
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
          You are helping generate content ideas. Here is the author persona:

          #{@config.persona}

          Here are recent items from idea sources:

          #{items_text}

          Generate #{@num} content ideas for #{@form}-form posts. #{form_instruction}

          For news/current-events items, suggest a specific angle or take.
          For opinion/essay items, use them as inspiration for related ideas.

          Format each idea exactly as:

          IDEA: <title>
          SOURCE: <source name>
          BODY:
          <content>

          ---

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
