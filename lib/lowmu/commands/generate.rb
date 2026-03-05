module Lowmu
  module Commands
    class Generate
      GENERATOR_MAP = {
        "substack_long" => Generators::SubstackLong,
        "substack_short" => Generators::SubstackShort,
        "mastodon_short" => Generators::MastodonShort,
        "linkedin_short" => Generators::LinkedinShort,
        "linkedin_long" => Generators::LinkedinLong
      }.freeze

      def initialize(key_filter = nil, config:, target: nil, force: false)
        @key_filter = key_filter
        @target_filter = target
        @force = force
        @config = config
        @store = ContentStore.new(config.content_dir)
      end

      def plan
        configure_llm
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter
        warn_stale(items)
        items.select { |item| should_generate?(item) }
          .flat_map { |item| plan_item(item) }
      end

      def call
        plan.map do |t|
          file = t[:generator].generate
          {key: t[:key], target: t[:target], file: file}
        end
      end

      private

      def plan_item(item)
        @store.ensure_slug_dir(item[:key])
        applicable_targets(item[:content_type]).map do |target_name|
          target_config = @config.target_config(target_name)
          generator_class = generator_class_for(target_name)
          generator = generator_class.new(
            @store.slug_dir(item[:key]),
            item[:source_path],
            item[:content_type],
            target_config,
            @config.llm
          )
          {key: item[:key], target: target_name, generator: generator}
        end
      end

      def should_generate?(item)
        status = item_status(item)
        return false if status == :ignore
        return true if @force
        if @key_filter
          status == :pending || status == :stale
        else
          status == :pending
        end
      end

      def warn_stale(items)
        items.each do |item|
          next unless item_status(item) == :stale
          next if should_generate?(item)
          warn "Warning: '#{item[:key]}' is stale. Run `lowmu generate #{item[:key]}` to regenerate."
        end
      end

      def item_status(item)
        @status_cache ||= {}
        @status_cache[item[:key]] ||= SlugStatus.new(item[:key], item[:source_path], @store).call
      end

      def applicable_targets(content_type)
        resolve_targets.reject do |target_name|
          content_type == :note && generator_class_for(target_name)::FORM == :long
        end
      end

      def generator_class_for(target_name)
        target_config = @config.target_config(target_name)
        GENERATOR_MAP.fetch(target_config["type"]) do
          raise Error, "Unknown target type: #{target_config["type"]}"
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
