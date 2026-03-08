module Lowmu
  module Commands
    class Status
      def initialize(key = nil, config:, filters: {})
        @key_filter = key
        @config = config
        @filters = filters
        @store = ContentStore.new(config.content_dir)
      end

      def call
        items = HugoScanner.new(
          @config.hugo_content_dir,
          post_dirs: @config.post_dirs,
          note_dirs: @config.note_dirs
        ).scan
        items = items.select { |item| item[:key] == @key_filter } if @key_filter

        rows = items.map do |item|
          statuses = InputStatus.new(item, @config.targets, @store).call
          {key: item[:key], source_path: item[:source_path], statuses: statuses}
        end

        {targets: @config.targets, rows: filter(rows)}
      end

      private

      def filter(rows)
        return rows if @filters.empty? || @filters[:all]
        rows.select { |row| matches_filter?(row) }
      end

      def matches_filter?(row)
        applicable = row[:statuses].reject { |_, s| s == :not_applicable }
        agg = aggregate(applicable.values)

        return applicable.values.any? { |s| s == :pending } if @filters[:pending]
        return applicable.values.none? { |s| s == :pending } if @filters[:no_pending]
        return agg == :done if @filters[:done]
        return agg == :partial if @filters[:partial]
        return applicable.values.any? { |s| s == :stale } if @filters[:stale]
        return applicable.values.none? { |s| s == :stale } if @filters[:no_stale]
        return recent_match?(row) if @filters[:recent]
        true
      end

      def aggregate(values)
        return :pending if values.none? { |s| s == :done || s == :stale }
        return :stale if values.any? { |s| s == :stale }
        return :done if values.all? { |s| s == :done }
        :partial
      end

      def recent_match?(row)
        duration = DurationParser.parse(@filters[:recent])
        cutoff = Time.now - duration
        output_paths = @config.targets.map do |type|
          File.join(@store.slug_dir(row[:key]), Generators.registry[type]::OUTPUT_FILE)
        end
        existing = output_paths.select { |p| File.exist?(p) }
        if existing.any?
          existing.any? { |p| File.mtime(p) >= cutoff }
        else
          File.mtime(row[:source_path]) >= cutoff
        end
      end
    end
  end
end
