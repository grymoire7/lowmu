require "spec_helper"

RSpec.describe Lowmu::RandomProcessingTitle do
  describe ".generate" do
    it "returns a two-element array" do
      expect(described_class.generate.length).to eq(2)
    end

    it "defaults to the :generic category" do
      result = described_class.generate
      expect(described_class::VERBS[:generic]).to include(result)
    end

    it "returns a pair from the requested category" do
      result = described_class.generate(:baking)
      expect(described_class::VERBS[:baking]).to include(result)
    end

    it "returns [present_participle, past_tense] strings" do
      present, past = described_class.generate
      expect(present).to be_a(String)
      expect(past).to be_a(String)
    end
  end
end
