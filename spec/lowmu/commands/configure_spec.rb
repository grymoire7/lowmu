require "spec_helper"

RSpec.describe Lowmu::Commands::Configure do
  let(:config_path) { File.join(Dir.mktmpdir, "config.yml") }

  describe "#call" do
    context "when no config file exists" do
      it "creates the config file" do
        described_class.new(config_path).call
        expect(File.exist?(config_path)).to be true
      end

      it "returns created: true and the path" do
        result = described_class.new(config_path).call
        expect(result[:created]).to be true
        expect(result[:path]).to eq(config_path)
      end

      it "writes a valid YAML template" do
        described_class.new(config_path).call
        data = YAML.safe_load_file(config_path)
        expect(data).to have_key("content_dir")
        expect(data).to have_key("targets")
      end
    end

    context "when a config file already exists" do
      before { File.write(config_path, "existing: true\n") }

      it "returns exists: true without overwriting" do
        result = described_class.new(config_path).call
        expect(result[:exists]).to be true
        expect(YAML.safe_load_file(config_path)).to eq({"existing" => true})
      end
    end
  end
end
