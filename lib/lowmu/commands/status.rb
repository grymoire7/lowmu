module Lowmu
  module Commands
    class Status
      def initialize(key = nil, config:)
        @key_filter = key
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter

        items.filter_map do |item|
          status = SlugStatus.new(item[:key], item[:source_path], @store).call
          next if status == :ignore
          {key: item[:key], status: status}
        end
      end
    end
  end
end
