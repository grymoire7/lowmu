module Lowmu
  module Generators
    class MastodonShort < Base
      FORM = :short
      OUTPUT_FILE = "mastodon_short.md"
      MAX_CHARS = 500

      POST_PROMPT = <<~PROMPT
        Write a Mastodon post announcing the following blog post. Requirements:
        - Must be under %d characters total (including the [URL] placeholder)
        - Capture the key insight or hook from the post
        - Use a conversational, authentic tone — not marketing speak
        - Include 2-3 relevant hashtags at the end
        - End with [URL] as a placeholder for the post URL

        Blog post:
        %s

        Return only the Mastodon post text.
      PROMPT

      NOTE_PROMPT = <<~PROMPT
        Condense the following note for Mastodon. Requirements:
        - Must be under %d characters total
        - Preserve the key point of the note
        - Maintain the author's voice and tone
        - Include 2-3 relevant hashtags at the end

        Note:
        %s

        Return only the Mastodon post text.
      PROMPT

      def generate
        content = if @content_type == :short
          loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
          parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
          body = parsed.content.strip
          (body.length <= MAX_CHARS) ? body : ask_llm(NOTE_PROMPT % [MAX_CHARS, body])
        else
          ask_llm(POST_PROMPT % [MAX_CHARS, original_content])
        end

        if content.length > MAX_CHARS
          content += "\n\n<!-- lowmu: content is #{content.length} chars, target is #{MAX_CHARS} chars. Please shorten before publishing. -->"
        end

        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
