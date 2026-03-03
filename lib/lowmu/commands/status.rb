module Lowmu
  module Commands
    class Status
      def initialize(slug = nil, config:)
        @slug_filter = slug
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        items = HugoScanner.new(@config.hugo_content_dir).scan
        items = items.select { |item| item[:slug] == @slug_filter } if @slug_filter

        items.map do |item|
          status = SlugStatus.new(item[:slug], item[:source_path], @store).call
          {slug: item[:slug], status: status}
        end
      end
    end
  end
end
