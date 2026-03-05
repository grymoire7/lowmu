module Lowmu
  module Generators
    class LinkedinLong < Base
      FORM = :long
      OUTPUT_FILE = "linkedin_long.md"

      PROMPT = <<~PROMPT
        Write a long-form LinkedIn article based on the following blog post. Requirements:
        - Professional tone with personal insights
        - Include a compelling headline
        - Expand on the key ideas with LinkedIn-appropriate formatting
        - 500-1000 words
        - End with a call to action

        Blog post:
        %s

        Return only the article content with headline.
      PROMPT

      def generate
        content = ask_llm(PROMPT % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
