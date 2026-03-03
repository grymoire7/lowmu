module Lowmu
  class ContentStore
    STATUS_FILE = "status.yml"
    ORIGINAL_CONTENT_FILE = "original_content.md"

    attr_reader :base_dir

    def self.slug_from_path(path)
      File.basename(path, File.extname(path))
    end

    def initialize(base_dir)
      @base_dir = File.expand_path(base_dir)
    end

    def slug_dir(slug)
      File.join(base_dir, slug)
    end

    def slug_exists?(slug)
      Dir.exist?(slug_dir(slug))
    end

    def ensure_slug_dir(slug)
      FileUtils.mkdir_p(slug_dir(slug))
    end

    def create_slug(slug, md_path, image_path)
      raise Error, "Slug already exists: #{slug}" if slug_exists?(slug)
      dir = slug_dir(slug)
      FileUtils.mkdir_p(dir)
      FileUtils.cp(md_path, File.join(dir, ORIGINAL_CONTENT_FILE))
      ext = File.extname(image_path)
      FileUtils.cp(image_path, File.join(dir, "hero_image#{ext}"))
    end

    def write_status(slug, status)
      File.write(File.join(slug_dir(slug), STATUS_FILE), status.to_yaml)
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

    def update_target_status(slug, target_name, status_attrs)
      current = read_status(slug)
      current[target_name] ||= {}
      current[target_name].merge!(status_attrs)
      write_status(slug, current)
    end

    def slugs
      return [] unless Dir.exist?(base_dir)
      Dir.children(base_dir).select { |f| Dir.exist?(File.join(base_dir, f)) }.sort
    end

    def original_content_path(slug)
      File.join(slug_dir(slug), ORIGINAL_CONTENT_FILE)
    end
  end
end
