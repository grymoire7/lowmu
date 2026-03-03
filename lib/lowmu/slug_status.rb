module Lowmu
  class SlugStatus
    def initialize(slug, source_path, content_store)
      @slug = slug
      @source_path = source_path
      @content_store = content_store
    end

    def call
      gen_at = @content_store.generated_at(@slug)
      return :pending unless gen_at

      (File.mtime(@source_path) > gen_at) ? :stale : :generated
    end
  end
end
