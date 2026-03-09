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
        id = atom_item?(item) ? (item.id&.content || item.link&.href) : (item.guid&.content || item.link)
        title = atom_item?(item) ? item.title&.content : item.title
        url = atom_item?(item) ? item.link&.href : item.link
        body = atom_item?(item) ? (item.content&.content || item.summary&.content || "") : (item.description || "")
        body = strip_html(body)
        excerpt = body.split.first(EXCERPT_WORDS).join(" ")
        {id: id, title: title, url: url, body: body, excerpt: excerpt, source_name: @name}
      end

      def atom_item?(item)
        item.is_a?(RSS::Atom::Feed::Entry)
      end

      def strip_html(html)
        html.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end
    end
  end
end
