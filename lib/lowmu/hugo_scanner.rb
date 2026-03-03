module Lowmu
  class HugoScanner
    def initialize(hugo_content_dir)
      @hugo_content_dir = File.expand_path(hugo_content_dir)
    end

    def scan
      Dir.glob("**/*.md", base: @hugo_content_dir).map do |rel_path|
        full_path = File.join(@hugo_content_dir, rel_path)
        {slug: derive_slug(full_path), source_path: full_path}
      end
    end

    private

    def derive_slug(path)
      content = File.read(path)
      loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
      parsed = FrontMatterParser::Parser.new(:md, loader: loader).call(content)

      fm = parsed.front_matter || {}
      return fm["slug"] if fm["slug"]

      if File.basename(path) == "index.md"
        File.basename(File.dirname(path))
      else
        File.basename(path, ".md")
      end
    end
  end
end
