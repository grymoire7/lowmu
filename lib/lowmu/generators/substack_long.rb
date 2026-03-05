module Lowmu
  module Generators
    class SubstackLong < Base
      FORM = :long
      OUTPUT_FILE = "substack_long.md"

      def generate
        loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
        parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
        write_output(OUTPUT_FILE, parsed.content)
        OUTPUT_FILE
      end
    end
  end
end
