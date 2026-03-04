module Lowmu
  class ContentStore
    IGNORE_FILE = "ignore.yml"

    attr_reader :base_dir

    def initialize(base_dir)
      @base_dir = File.expand_path(base_dir)
    end

    def slug_dir(key)
      File.join(base_dir, "generated", key)
    end

    def slug_exists?(key)
      Dir.exist?(slug_dir(key))
    end

    def ensure_slug_dir(key)
      FileUtils.mkdir_p(slug_dir(key))
    end

    def ignore_slugs
      path = File.join(base_dir, IGNORE_FILE)
      return [] unless File.exist?(path)
      YAML.safe_load_file(path) || []
    end

    def slugs
      generated_dir = File.join(base_dir, "generated")
      return [] unless Dir.exist?(generated_dir)
      Dir.children(generated_dir)
        .select { |section| Dir.exist?(File.join(generated_dir, section)) }
        .flat_map do |section|
          section_dir = File.join(generated_dir, section)
          Dir.children(section_dir)
            .select { |f| Dir.exist?(File.join(section_dir, f)) }
            .map { |slug| "#{section}/#{slug}" }
        end
        .sort
    end
  end
end
