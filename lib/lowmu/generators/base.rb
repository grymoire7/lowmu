module Lowmu
  module Generators
    class Base
      def initialize(slug_dir, target_config, llm_config)
        @slug_dir = slug_dir
        @target_config = target_config
        @llm_config = llm_config
      end

      def generate
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      private

      def original_content
        @original_content ||= File.read(File.join(@slug_dir, ContentStore::ORIGINAL_CONTENT_FILE))
      end

      def write_output(filename, content)
        File.write(File.join(@slug_dir, filename), content)
      end

      def ask_llm(prompt)
        model = @llm_config.fetch("model", "claude-opus-4-6")
        RubyLLM.chat(model: model).ask(prompt).content
      end
    end
  end
end
