module Lowmu
  module Publishers
    class Substack < Base
      def publish
        raise Error, "Substack direct publishing is not yet supported. " \
          "Your generated content is at: #{File.join(@slug_dir, Generators::Substack::OUTPUT_FILE)}"
      end
    end
  end
end
