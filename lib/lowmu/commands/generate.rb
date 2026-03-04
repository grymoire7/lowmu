module Lowmu
  module Commands
    class Generate
      GENERATOR_MAP = {
        "substack" => Generators::Substack,
        "mastodon" => Generators::Mastodon,
        "linkedin" => Generators::Linkedin
      }.freeze

      def initialize(slug_filter = nil, config:, target: nil, force: false)
        @slug_filter = slug_filter
        @target_filter = target
        @force = force
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def call
        configure_llm
        items = HugoScanner.new(@config.hugo_content_dir).scan
        items = items.select { |item| item[:slug] == @slug_filter } if @slug_filter
        warn_stale(items)
        items.select { |item| should_generate?(item) }
          .flat_map { |item| generate_slug(item) }
      end

      private

      def should_generate?(item)
        status = slug_status(item)
        return false if status == :ignore
        return true if @force
        if @slug_filter
          status == :pending || status == :stale
        else
          status == :pending
        end
      end

      def warn_stale(items)
        items.each do |item|
          next unless slug_status(item) == :stale
          next if should_generate?(item)
          warn "Warning: '#{item[:slug]}' is stale. Run `lowmu generate #{item[:slug]}` to regenerate."
        end
      end

      def slug_status(item)
        @status_cache ||= {}
        @status_cache[item[:slug]] ||= SlugStatus.new(item[:slug], item[:source_path], @store).call
      end

      def generate_slug(item)
        @store.ensure_slug_dir(item[:slug])

        resolve_targets.map do |target_name|
          target_config = @config.target_config(target_name)
          generator_class = GENERATOR_MAP.fetch(target_config["type"]) do
            raise Error, "Unknown target type: #{target_config["type"]}"
          end

          output_file = generator_class.new(
            @store.slug_dir(item[:slug]),
            item[:source_path],
            item.fetch(:content_type, :post),
            target_config,
            @config.llm
          ).generate

          {slug: item[:slug], target: target_name, file: output_file}
        end
      end

      def resolve_targets
        if @target_filter
          unless @config.targets.any? { |t| t["name"] == @target_filter }
            raise Error, "Unknown target: #{@target_filter}"
          end
          [@target_filter]
        else
          @config.targets.map { |t| t["name"] }
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
