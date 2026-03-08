require "rss"
require "open-uri"

module Lowmu
  module Sources
    class RssSource
      EXCERPT_WORDS = 200

      def initialize(name:, url:)
        @name = name
        @url = url
      end

      def items
        @items ||= begin
          feed = RSS::Parser.parse(URI.open(@url).read, false) # standard:disable Security/Open
          feed.items.map { |item| parse_item(item) }
        end
      end

      private

      def parse_item(item)
        id = item.guid&.content || item.link
        title = item.title
        body = item.description || ""
        excerpt = strip_html(body).split.first(EXCERPT_WORDS).join(" ")
        {id: id, title: title, excerpt: excerpt, source_name: @name}
      end

      def strip_html(html)
        html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end
    end
  end
end
