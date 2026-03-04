module Lowmu
  class ContentStore
    IGNORE_FILE = "ignore.yml"

    attr_reader :base_dir

    def initialize(base_dir)
      @base_dir = File.expand_path(base_dir)
    end

    def slug_dir(slug)
      File.join(base_dir, "generated", slug)
    end

    def slug_exists?(slug)
      Dir.exist?(slug_dir(slug))
    end

    def ensure_slug_dir(slug)
      FileUtils.mkdir_p(slug_dir(slug))
    end

    def ignore_slugs
      path = File.join(base_dir, IGNORE_FILE)
      return [] unless File.exist?(path)
      YAML.safe_load_file(path) || []
    end

    def slugs
      generated_dir = File.join(base_dir, "generated")
      return [] unless Dir.exist?(generated_dir)
      Dir.children(generated_dir).select { |f| Dir.exist?(File.join(generated_dir, f)) }.sort
    end
  end
end
