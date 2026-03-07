module Lowmu
  module Commands
    class Generate
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
        applicable_targets(item[:content_type]).map do |type|
          generator_class = generator_class_for(type)
          generator = generator_class.new(
            @store.slug_dir(item[:key]),
            item[:source_path],
            item[:content_type],
            {},
            @config.llm
          )
          {key: item[:key], target: type, generator: generator}
        end
      end

      def should_generate?(item)
        status = item_status(item)
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
        @status_cache[item[:key]] ||= InputStatus.new(item, @config.targets, @store).aggregate
      end

      def applicable_targets(content_type)
        resolve_targets.reject do |type|
          content_type == :short && Generators.registry[type]::FORM == :long
        end
      end

      def generator_class_for(type)
        Generators.registry.fetch(type) do
          raise Error, "Unknown target type: #{type}"
        end
      end

      def resolve_targets
        if @target_filter
          unless @config.targets.include?(@target_filter)
            raise Error, "Unknown target: #{@target_filter}"
          end
          [@target_filter]
        else
          @config.targets
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
