require "date"

module Lowmu
  class IdeaWriter
    def initialize(ideas_dir)
      @ideas_dir = ideas_dir
      FileUtils.mkdir_p(@ideas_dir)
    end

    def write(title:, form:, concept_source:, angle_source:, audience_source:, examples_source:, conclusion_source:, body:)
      slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
      filename = "#{form}-#{slug}.md"
      content = <<~MD
        ---
        title: #{title.inspect}
        form: #{form}
        concept_source: #{concept_source}
        angle_source: #{angle_source}
        audience_source: #{audience_source}
        examples_source: #{examples_source}
        conclusion_source: #{conclusion_source}
        date: #{Date.today}
        ---

        #{body}
      MD
      File.write(File.join(@ideas_dir, filename), content)
      filename
    end
  end
end
