module Lowmu
  module Commands
    class Generate
      GENERATOR_MAP = {
        "hugo" => Generators::Hugo,
        "substack" => Generators::Substack,
        "mastodon" => Generators::Mastodon,
        "linkedin" => Generators::Linkedin
      }.freeze

      def initialize(slug, config:, target: nil, force: false)
        @slug = slug
        @target_filter = target
        @force = force
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        raise Error, "Slug not found: #{@slug}" unless @store.slug_exists?(@slug)

        configure_llm
        resolve_targets.map { |target_name| generate_target(target_name) }
      end

      private

      def generate_target(target_name)
        target_config = @config.target_config(target_name)
        current_status = @store.read_status(@slug).dig(target_name, "status")

        if current_status == "generated" && !@force
          raise Error, "Target '#{target_name}' already generated. Use --force to regenerate."
        end

        generator_class = GENERATOR_MAP.fetch(target_config["type"]) do
          raise Error, "Unknown target type: #{target_config["type"]}"
        end

        output_file = generator_class.new(@store.slug_dir(@slug), target_config, @config.llm).generate
        @store.update_target_status(@slug, target_name, {"status" => "generated", "file" => output_file})

        {target: target_name, file: output_file}
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

      def configure_llm
        RubyLLM.configure do |c|
          c.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
        end
      end
    end
  end
end
