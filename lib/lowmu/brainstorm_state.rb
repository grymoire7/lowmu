module Lowmu
  class BrainstormState
    def initialize(content_dir)
      @path = File.join(File.expand_path(content_dir), "brainstorm_state.yml")
    end

    def cached?(source_name, id)
      source_items(source_name).key?(id)
    end

    def cache_path_for(source_name, id)
      source_items(source_name)[id]
    end

    def mark_cached(source_name, id, relative_path)
      data["sources"] ||= {}
      data["sources"][source_name] ||= {}
      data["sources"][source_name]["cached_items"] ||= {}
      data["sources"][source_name]["cached_items"][id] = relative_path
      File.write(@path, data.to_yaml)
    end

    private

    def source_items(source_name)
      data.dig("sources", source_name, "cached_items") || {}
    end

    def data
      @data ||= if File.exist?(@path)
        YAML.safe_load_file(@path) || {}
      else
        {}
      end
    end
  end
end
