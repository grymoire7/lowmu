module Lowmu
  module Generators
    class LinkedinShort < Base
      FORM = :short
      OUTPUT_FILE = "linkedin_short.md"

      POST_PROMPT = <<~PROMPT
        Write a LinkedIn post based on the following blog post. Requirements:
        - Professional but conversational tone
        - Lead with a strong hook (the first line is critical on LinkedIn)
        - Summarize key insights in 3-5 short paragraphs or bullet points
        - End with "Read the full post: [URL]"
        - Between 150-300 words total

        Blog post:
        %s

        Return only the LinkedIn post text.
      PROMPT

      NOTE_PROMPT = <<~PROMPT
        Write a LinkedIn post based on the following short note. Requirements:
        - Professional but conversational tone
        - Lead with the key insight
        - Keep it concise, 1-2 short paragraphs
        - 50-150 words total

        Note:
        %s

        Return only the LinkedIn post text.
      PROMPT

      def generate
        prompt = (@content_type == :short) ? NOTE_PROMPT : POST_PROMPT
        content = ask_llm(prompt % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
