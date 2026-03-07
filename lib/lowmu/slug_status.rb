module Lowmu
  class SlugStatus
    def initialize(key, source_path, content_store)
      @key = key
      @source_path = source_path
      @content_store = content_store
    end

    def call
      slug_dir = @content_store.slug_dir(@key)
      return :pending unless Dir.exist?(slug_dir)

      files = Dir.children(slug_dir).map { |f| File.join(slug_dir, f) }.select { |f| File.file?(f) }
      return :pending if files.empty?

      oldest_generated = files.map { |f| File.mtime(f) }.min
      (File.mtime(@source_path) > oldest_generated) ? :stale : :generated
    end
  end
end
