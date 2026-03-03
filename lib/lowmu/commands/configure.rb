module Lowmu
  module Commands
    class Configure
      TEMPLATE_PATH = File.expand_path("../templates/default_config.yml", __dir__)

      def initialize(path = Config::DEFAULT_PATH)
        @path = File.expand_path(path)
      end

      def call
        if File.exist?(@path)
          {exists: true, path: @path}
        else
          FileUtils.mkdir_p(File.dirname(@path))
          FileUtils.cp(TEMPLATE_PATH, @path)
          {created: true, path: @path}
        end
      end
    end
  end
end
