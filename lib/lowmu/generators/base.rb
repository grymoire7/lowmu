module Lowmu
  module Generators
    class Base
      def initialize(slug_dir, source_path, content_type, target_config, llm_config)
        @slug_dir = slug_dir
        @source_path = source_path
        @content_type = content_type
        @target_config = target_config
        @llm_config = llm_config
      end

      def generate
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      private

      def original_content
        @original_content ||= File.read(@source_path)
      end

      def write_output(filename, content)
        File.write(File.join(@slug_dir, filename), content)
      end

      def ask_llm(prompt)
        model = @llm_config.fetch("model") do
          raise Error, "No model configured. Run `lowmu configure` to set up an LLM provider."
        end
        RubyLLM.chat(model: model).ask(prompt).content
      end
    end
  end
end
