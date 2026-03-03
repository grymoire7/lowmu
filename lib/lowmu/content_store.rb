module Lowmu
  class ContentStore
    STATUS_FILE = "status.yml"

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

    def write_status(slug, status)
      dir = slug_dir(slug)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, STATUS_FILE), status.to_yaml)
    end

    def read_status(slug)
      path = File.join(slug_dir(slug), STATUS_FILE)
      YAML.safe_load_file(path) || {}
    rescue Errno::ENOENT
      {}
    end

    def generated_at(slug)
      val = read_status(slug)["generated_at"]
      val ? Time.iso8601(val.to_s) : nil
    end

    def slugs
      generated_dir = File.join(base_dir, "generated")
      return [] unless Dir.exist?(generated_dir)
      Dir.children(generated_dir).select { |f| Dir.exist?(File.join(generated_dir, f)) }.sort
    end
  end
end
