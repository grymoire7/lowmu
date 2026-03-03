module Lowmu
  module Publishers
    class Base
      def initialize(slug_dir, target_config)
        @slug_dir = slug_dir
        @target_config = target_config
      end

      def publish
        raise NotImplementedError, "#{self.class} must implement #publish"
      end

      private

      def generated_file_path(filename)
        path = File.join(@slug_dir, filename)
        raise Error, "Generated file not found: #{filename}. Run `lowmu generate` first." unless File.exist?(path)
        path
      end
    end
  end
end
