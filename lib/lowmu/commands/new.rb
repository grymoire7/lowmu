module Lowmu
  module Commands
    class New
      def initialize(md_path, hero_image_path, config:)
        @md_path = File.expand_path(md_path)
        @hero_image_path = File.expand_path(hero_image_path)
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        validate!
        slug = ContentStore.slug_from_path(@md_path)
        targets = parse_targets

        @store.create_slug(slug, @md_path, @hero_image_path)

        initial_status = targets.each_with_object({}) do |target, hash|
          hash[target] = {"status" => "pending"}
        end
        @store.write_status(slug, initial_status)

        {slug: slug, targets: targets}
      end

      private

      def validate!
        raise Error, "Markdown file not found: #{@md_path}" unless File.exist?(@md_path)
        raise Error, "Hero image not found: #{@hero_image_path}" unless File.exist?(@hero_image_path)
      end

      def parse_targets
        loader = FrontMatterParser::Loader::Yaml.new(allowlist_classes: [Date])
        parsed = FrontMatterParser::Parser.parse_file(@md_path, loader: loader)
        parsed.front_matter.fetch("publish_to", [])
      end
    end
  end
end
