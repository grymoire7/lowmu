require "digest"

module Lowmu
  module Sources
    class FileSource
      EXCERPT_WORDS = 200

      def initialize(name:, path:)
        @name = name
        @path = File.expand_path(path)
      end

      def items
        content = File.read(@path)
        sections = content.split(/^(?=## )/).reject(&:empty?)
        sections.map { |section| parse_section(section) }
      end

      private

      def parse_section(section)
        lines = section.strip.lines
        title = lines.first.to_s.sub(/^##\s*/, "").strip
        body = lines.drop(1).join.strip
        id = Digest::SHA1.hexdigest("#{@name}:#{title}")[0, 8]
        excerpt = body.split.first(EXCERPT_WORDS).join(" ")
        {id: id, title: title, excerpt: excerpt, source_name: @name}
      end
    end
  end
end
