require "spec_helper"

RSpec.describe Lowmu::Sources::RssSource do
  let(:fixture_xml) { File.read("spec/fixtures/sample_feed.xml") }
  let(:source) { described_class.new(name: "example-blog", url: "https://example.com/feed.xml") }

  before do
    allow(URI).to receive(:open).with("https://example.com/feed.xml").and_return(StringIO.new(fixture_xml))
  end

  describe "#items" do
    it "returns an array of item hashes" do
      expect(source.items).to be_an(Array)
      expect(source.items.length).to eq(2)
    end

    it "includes id, title, excerpt, and source_name" do
      item = source.items.first
      expect(item[:id]).to eq("https://example.com/first-post")
      expect(item[:title]).to eq("First Post About Ruby")
      expect(item[:excerpt]).to include("Ruby is a great language")
      expect(item[:source_name]).to eq("example-blog")
    end

    it "uses link as id when guid is absent" do
      xml = fixture_xml.gsub(/<guid>.*?<\/guid>/, "")
      allow(URI).to receive(:open).and_return(StringIO.new(xml))
      expect(source.items.first[:id]).to eq("https://example.com/first-post")
    end

    it "strips HTML tags from excerpt" do
      xml = fixture_xml.gsub("Ruby is a great language", "<strong>Ruby</strong> is a great language")
      allow(URI).to receive(:open).and_return(StringIO.new(xml))
      expect(source.items.first[:excerpt]).not_to include("<strong>")
      expect(source.items.first[:excerpt]).to include("Ruby")
    end

    it "includes body (full stripped HTML content)" do
      item = source.items.first
      expect(item).to have_key(:body)
      expect(item[:body]).to be_a(String)
    end

    it "includes url" do
      item = source.items.first
      expect(item).to have_key(:url)
      expect(item[:url]).to eq("https://example.com/first-post")
    end

    context "with an Atom feed" do
      let(:fixture_xml) { File.read("spec/fixtures/sample_atom_feed.xml") }

      it "returns an array of item hashes" do
        expect(source.items).to be_an(Array)
        expect(source.items.length).to eq(2)
      end

      it "includes id, title, excerpt, and source_name" do
        item = source.items.first
        expect(item[:id]).to eq("https://example.com/first-atom-post")
        expect(item[:title]).to eq("First Atom Post About Ruby")
        expect(item[:excerpt]).to include("Ruby is a great language")
        expect(item[:source_name]).to eq("example-blog")
      end
    end
  end
end
