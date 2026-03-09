require "spec_helper"

RSpec.describe Lowmu::IdeaWriter do
  let(:ideas_dir) { Dir.mktmpdir("lowmu_ideas_test") }
  let(:writer) { described_class.new(ideas_dir) }

  after { FileUtils.rm_rf(ideas_dir) }

  describe "#write" do
    let(:filename) do
      writer.write(
        title: "Ruby Metaprogramming Tips",
        form: "long",
        concept_source: "blog-a",
        angle_source: "blog-b",
        audience_source: "blog-c",
        examples_source: "blog-d",
        conclusion_source: "blog-e",
        body: "Here is a great idea about metaprogramming."
      )
    end

    it "returns a filename starting with the form" do
      expect(filename).to start_with("long-")
    end

    it "returns a filename ending with .md" do
      expect(filename).to end_with(".md")
    end

    it "slugifies the title in the filename" do
      expect(filename).to include("ruby-metaprogramming-tips")
    end

    it "creates the file in the ideas directory" do
      expect(File.exist?(File.join(ideas_dir, filename))).to be true
    end

    it "writes YAML front matter with title, form, sources, and date" do
      content = File.read(File.join(ideas_dir, filename))
      expect(content).to include("title: \"Ruby Metaprogramming Tips\"")
      expect(content).to include("form: long")
      expect(content).to include("concept_source: blog-a")
      expect(content).to include("angle_source: blog-b")
      expect(content).to include("audience_source: blog-c")
      expect(content).to include("examples_source: blog-d")
      expect(content).to include("conclusion_source: blog-e")
      expect(content).to include("date: #{Date.today}")
    end

    it "writes the body after front matter" do
      content = File.read(File.join(ideas_dir, filename))
      expect(content).to include("Here is a great idea about metaprogramming.")
    end

    it "creates the ideas directory if it does not exist" do
      new_dir = File.join(Dir.mktmpdir, "new_ideas")
      described_class.new(new_dir).write(title: "Test", form: "short", concept_source: "s", angle_source: "s", audience_source: "s", examples_source: "s", conclusion_source: "s", body: "b")
      expect(Dir.exist?(new_dir)).to be true
    end
  end
end
