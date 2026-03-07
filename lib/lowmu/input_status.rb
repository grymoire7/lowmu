module Lowmu
  class InputStatus
    def initialize(item, enabled_targets, content_store)
      @key = item[:key]
      @source_path = item[:source_path]
      @content_type = item[:content_type]
      @enabled_targets = enabled_targets
      @content_store = content_store
    end

    def call
      @result ||= @enabled_targets.each_with_object({}) do |type, hash|
        generator_class = Generators.registry[type]
        hash[type] = target_status(generator_class)
      end
    end

    def aggregate
      applicable = call.reject { |_, s| s == :not_applicable }.values
      return :pending if applicable.none? { |s| s == :done || s == :stale }
      return :stale if applicable.any? { |s| s == :stale }
      return :done if applicable.all? { |s| s == :done }
      :partial
    end

    private

    def target_status(generator_class)
      return :not_applicable if @content_type == :short && generator_class::FORM == :long

      output_path = File.join(@content_store.slug_dir(@key), generator_class::OUTPUT_FILE)
      return :pending unless File.exist?(output_path)

      (File.mtime(@source_path) > File.mtime(output_path)) ? :stale : :done
    end
  end
end
