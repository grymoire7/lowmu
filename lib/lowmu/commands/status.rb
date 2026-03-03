module Lowmu
  module Commands
    class Status
      def initialize(slug = nil, config:)
        @slug = slug
        @store = ContentStore.new(config.content_dir)
      end

      def call
        slugs = @slug ? [@slug] : @store.slugs
        slugs.map do |s|
          {slug: s, targets: @store.read_status(s)}
        end
      end
    end
  end
end
