module Lowmu
  module Generators
    class Mastodon < Base
      OUTPUT_FILE = "mastodon.txt"
      MAX_CHARS = 500

      PROMPT = <<~PROMPT
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

      def generate
        content = ask_llm(PROMPT % [MAX_CHARS, original_content])
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
