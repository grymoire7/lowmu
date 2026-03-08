require "spec_helper"

RSpec.describe Lowmu::Sources::FileSource do
  let(:source) { described_class.new(name: "my-ideas", path: "spec/fixtures/sample_ideas.md") }

  describe "#items" do
    it "returns one item per ## heading" do
      expect(source.items.length).to eq(2)
    end

    it "uses the heading as title" do
      expect(source.items.first[:title]).to eq("Idea One About Ruby Metaprogramming")
    end

    it "includes excerpt from section body" do
      expect(source.items.first[:excerpt]).to include("metaprogramming")
    end

    it "sets source_name" do
      expect(source.items.first[:source_name]).to eq("my-ideas")
    end

    it "generates a stable id from source name and heading" do
      id1 = source.items.first[:id]
      id2 = described_class.new(name: "my-ideas", path: "spec/fixtures/sample_ideas.md").items.first[:id]
      expect(id1).to eq(id2)
    end

    it "generates different ids for different headings" do
      ids = source.items.map { |i| i[:id] }
      expect(ids.uniq.length).to eq(ids.length)
    end
  end
end
