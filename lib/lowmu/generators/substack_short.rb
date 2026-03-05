module Lowmu
  module Generators
    class SubstackShort < Base
      FORM = :short
      OUTPUT_FILE = "substack_short.md"

      NOTE_FROM_POST_PROMPT = <<~PROMPT
        Write a short Substack note announcing the following blog post. Requirements:
        - Should be 2-4 sentences
        - Capture the key hook or insight from the post
        - Use a conversational, authentic tone
        - End with [URL] as a placeholder for the post URL

        Blog post:
        %s

        Return only the note text.
      PROMPT

      def generate
        if @content_type == :short
          loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
          parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
          write_output(OUTPUT_FILE, parsed.content.strip)
        else
          content = ask_llm(NOTE_FROM_POST_PROMPT % original_content)
          write_output(OUTPUT_FILE, content)
        end
        OUTPUT_FILE
      end
    end
  end
end
