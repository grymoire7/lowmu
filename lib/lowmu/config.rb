module Lowmu
  class Config
    DEFAULT_PATH = "~/.config/lowmu/config.yml"

    attr_reader :hugo_content_dir, :content_dir, :llm, :targets, :post_dirs, :note_dirs

    def self.load(path = DEFAULT_PATH)
      expanded = File.expand_path(path)
      unless File.exist?(expanded)
        raise Error, "Config file not found at #{expanded}. Run `lowmu configure` to create one."
      end
      data = YAML.safe_load_file(expanded) || {}
      new(data)
    end

    def initialize(data)
      @hugo_content_dir = File.expand_path(fetch!(data, "hugo_content_dir"))
      @content_dir = File.expand_path(data.fetch("content_dir", ".lowmu"))
      @llm = data.fetch("llm", {})
      @targets = parse_targets(data.fetch("targets", []))
      @post_dirs = data.fetch("post_dirs", ["posts"])
      @note_dirs = data.fetch("note_dirs", ["notes"])
    end

    def target_config(name)
      targets.find { |t| t["name"] == name } ||
        raise(Error, "Unknown target: #{name}")
    end

    private

    def fetch!(data, key)
      data.fetch(key) { raise Error, "Config missing required key: #{key}" }
    end

    def parse_targets(targets)
      targets.map do |t|
        raise Error, "Target missing required key: name" unless t["name"]
        raise Error, "Target missing required key: type" unless t["type"]
        t
      end
    end
  end
end
