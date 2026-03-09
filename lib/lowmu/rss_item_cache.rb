require "date"

module Lowmu
  class RssItemCache
    EXCERPT_WORDS = 200

    def initialize(content_dir)
      @content_dir = File.expand_path(content_dir)
      @cache_dir = File.join(@content_dir, "rss", "cache")
      FileUtils.mkdir_p(@cache_dir)
    end

    def write(item)
      relative_path = File.join("rss", "cache", filename_for(item))
      full_content = item[:body].split.length > EXCERPT_WORDS
      content = <<~MD
        ---
        title: #{item[:title].inspect}
        url: #{item[:url]}
        source_name: #{item[:source_name]}
        fetched_at: #{Date.today}
        full_content: #{full_content}
        ---

        #{item[:body]}
      MD
      File.write(File.join(@content_dir, relative_path), content)
      relative_path
    end

    private

    def filename_for(item)
      slug = item[:title].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      source_slug = item[:source_name].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      "#{Date.today}-#{source_slug}-#{slug}.md"
    end
  end
end
