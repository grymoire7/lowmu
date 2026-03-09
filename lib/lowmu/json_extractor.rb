# frozen_string_literal: true

module Lowmu
  # This class was made to handle the common case of LLM responses that are
  # either raw JSON or contain a JSON object somewhere in the text. It tries
  # multiple strategies to extract a JSON object, including:
  # - Parsing the entire content as JSON
  # - Stripping code block markers and parsing again
  # - Finding the first balanced JSON object in the text
  # If all strategies fail, it raises a JSON::ParserError.
  module JsonExtractor
    def self.call(content)
      return content if content.is_a?(Hash)

      try_parse(content) ||
        try_parse(content.gsub(/\A```\w*\s*|\s*```\z/m, "").strip) ||
        extract_first_object(content) ||
        raise(JSON::ParserError, "No JSON object found in response")
    end

    def self.try_parse(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :try_parse

    def self.extract_first_object(text)
      start = text.index("{")
      return nil unless start

      depth = 0
      in_string = false
      escape = false

      text[start..].chars.each_with_index do |char, i|
        if escape
          escape = false
        elsif char == "\\"
          escape = true if in_string
        elsif char == '"'
          in_string = !in_string
        elsif !in_string
          depth += 1 if char == "{"
          if char == "}"
            depth -= 1
            return try_parse(text[start, i + 1]) if depth.zero?
          end
        end
      end
      nil
    end
    private_class_method :extract_first_object
  end
end
