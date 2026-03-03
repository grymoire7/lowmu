module Lowmu
  module Generators
    class Linkedin < Base
      OUTPUT_FILE = "linkedin.md"

      PROMPT = <<~PROMPT
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

      def generate
        content = ask_llm(PROMPT % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
