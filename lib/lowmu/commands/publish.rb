module Lowmu
  module Commands
    class Publish
      PUBLISHER_MAP = {
        "hugo" => Publishers::Hugo,
        "substack" => Publishers::Substack,
        "mastodon" => Publishers::Mastodon
      }.freeze

      def initialize(slug, config:, target: nil)
        @slug = slug
        @target_filter = target
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        raise Error, "Slug not found: #{@slug}" unless @store.slug_exists?(@slug)
        resolve_targets.map { |target_name| publish_target(target_name) }
      end

      private

      def publish_target(target_name)
        target_config = @config.target_config(target_name)
        current_status = @store.read_status(@slug).dig(target_name, "status")

        unless current_status == "generated"
          raise Error, "Target '#{target_name}' is not in generated state (current: #{current_status}). Run `lowmu generate` first."
        end

        if target_config["type"] == "linkedin"
          return publish_linkedin(target_name, target_config)
        end

        publisher_class = PUBLISHER_MAP.fetch(target_config["type"]) do
          raise Error, "Unknown target type: #{target_config["type"]}"
        end

        publisher_class.new(@store.slug_dir(@slug), target_config).publish
        @store.update_target_status(@slug, target_name, {
          "status" => "published",
          "published_at" => Time.now.iso8601
        })

        {target: target_name, status: :published}
      end

      def publish_linkedin(target_name, _target_config)
        linkedin_file = File.join(@store.slug_dir(@slug), Generators::Linkedin::OUTPUT_FILE)
        @store.update_target_status(@slug, target_name, {
          "status" => "published",
          "published_at" => Time.now.iso8601,
          "note" => "Manual copy-paste required"
        })
        {target: target_name, status: :manual, file: linkedin_file}
      end

      def resolve_targets
        all_targets = @store.read_status(@slug).keys
        if @target_filter
          raise Error, "Target '#{@target_filter}' not in publish_to list" unless all_targets.include?(@target_filter)
          [@target_filter]
        else
          all_targets
        end
      end
    end
  end
end
