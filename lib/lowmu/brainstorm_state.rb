module Lowmu
  class BrainstormState
    def initialize(content_dir)
      @path = File.join(File.expand_path(content_dir), "brainstorm_state.yml")
    end

    def seen?(source_name, id)
      data.dig("sources", source_name, "last_seen_ids")&.include?(id) || false
    end

    def mark_seen(source_name, ids)
      data["sources"] ||= {}
      data["sources"][source_name] ||= {}
      existing = data["sources"][source_name]["last_seen_ids"] || []
      data["sources"][source_name]["last_seen_ids"] = (existing + ids).uniq
      File.write(@path, data.to_yaml)
    end

    private

    def data
      @data ||= if File.exist?(@path)
        YAML.safe_load_file(@path) || {}
      else
        {}
      end
    end
  end
end
