require "spec_helper"

RSpec.describe Lowmu::DurationParser do
  describe ".parse" do
    it "parses days" do
      expect(described_class.parse("3d")).to eq(3 * 86_400)
    end

    it "parses weeks" do
      expect(described_class.parse("1w")).to eq(7 * 86_400)
    end

    it "parses multi-digit values" do
      expect(described_class.parse("14d")).to eq(14 * 86_400)
    end

    it "raises for an unknown unit" do
      expect { described_class.parse("2m") }
        .to raise_error(Lowmu::Error, /Invalid duration/)
    end

    it "raises for a non-numeric value" do
      expect { described_class.parse("banana") }
        .to raise_error(Lowmu::Error, /Invalid duration/)
    end

    it "raises for empty string" do
      expect { described_class.parse("") }
        .to raise_error(Lowmu::Error, /Invalid duration/)
    end
  end
end
