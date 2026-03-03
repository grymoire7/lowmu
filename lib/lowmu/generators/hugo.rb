module Lowmu
  module Generators
    class Hugo < Base
      OUTPUT_FILE = "hugo.md"

      FRONT_MATTER_KEYS = %w[title date tags draft].freeze

      def generate
        loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
        parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(original_content)
        fm = parsed.front_matter

        hugo_fm = fm.slice(*FRONT_MATTER_KEYS).merge("draft" => false)
        output = "---\n#{hugo_fm.to_yaml.sub(/\A---\n/, "")}---\n\n#{parsed.content.strip}\n"

        write_output(OUTPUT_FILE, output)
        OUTPUT_FILE
      end
    end
  end
end
