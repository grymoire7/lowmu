require "date"

module Lowmu
  class IdeaWriter
    def initialize(ideas_dir)
      @ideas_dir = ideas_dir
      FileUtils.mkdir_p(@ideas_dir)
    end

    def write(title:, form:, source_name:, body:)
      slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      filename = "#{form}-#{slug}.md"
      content = <<~MD
        ---
        title: #{title.inspect}
        form: #{form}
        source: #{source_name}
        date: #{Date.today}
        ---

        #{body}
      MD
      File.write(File.join(@ideas_dir, filename), content)
      filename
    end
  end
end
