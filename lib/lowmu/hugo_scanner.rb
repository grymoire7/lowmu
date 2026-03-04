module Lowmu
  class HugoScanner
    def initialize(hugo_content_dir, post_dirs: ["posts"], note_dirs: ["notes"])
      @hugo_content_dir = File.expand_path(hugo_content_dir)
      @post_dirs = post_dirs
      @note_dirs = note_dirs
    end

    def scan
      results = []
      @post_dirs.each { |dir| results += scan_section(dir, :post) }
      @note_dirs.each { |dir| results += scan_section(dir, :note) }
      results
    end

    private

    def scan_section(section, content_type)
      full_dir = File.join(@hugo_content_dir, section)
      return [] unless Dir.exist?(full_dir)

      Dir.glob("**/*.md", base: full_dir).map do |rel_path|
        full_path = File.join(full_dir, rel_path)
        slug = derive_slug(full_path)
        {
          slug: slug,
          section: section,
          content_type: content_type,
          source_path: full_path,
          key: "#{section}/#{slug}"
        }
      end
    end

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
