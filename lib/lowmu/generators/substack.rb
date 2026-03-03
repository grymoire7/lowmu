module Lowmu
  module Generators
    class Substack < Base
      OUTPUT_FILE = "substack.md"

      PROMPT = <<~PROMPT
        Reformat the following markdown blog post for publication on Substack.
        Keep the full content intact. Ensure the markdown is clean and readable.
        Remove any Hugo-specific front matter fields — return only the body content
        with no front matter at all. Preserve the author's voice and tone exactly.

        Original post:
        %s

        Return only the formatted markdown content.
      PROMPT

      def generate
        content = ask_llm(PROMPT % original_content)
        write_output(OUTPUT_FILE, content)
        OUTPUT_FILE
      end
    end
  end
end
