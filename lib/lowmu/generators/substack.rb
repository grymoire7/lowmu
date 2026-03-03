module Lowmu
  module Generators
    class Substack < Base
      POST_FILE = "substack_post.md"
      NOTE_FILE = "substack_note.md"

      POST_PROMPT = <<~PROMPT
        Reformat the following markdown blog post for publication on Substack.
        Keep the full content intact. Ensure the markdown is clean and readable.
        Remove any front matter — return only the body content with no front matter at all.
        Preserve the author's voice and tone exactly.

        Original post:
        %s

        Return only the formatted markdown content.
      PROMPT

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
        loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
        parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
        input_type = parsed.front_matter.fetch("type", "post")

        if input_type == "note"
          write_output(NOTE_FILE, parsed.content.strip)
          NOTE_FILE
        else
          generate_post
          generate_note_from_post
          POST_FILE
        end
      end

      private

      def generate_post
        content = ask_llm(POST_PROMPT % original_content)
        write_output(POST_FILE, content)
      end

      def generate_note_from_post
        content = ask_llm(NOTE_FROM_POST_PROMPT % original_content)
        write_output(NOTE_FILE, content)
      end
    end
  end
end
