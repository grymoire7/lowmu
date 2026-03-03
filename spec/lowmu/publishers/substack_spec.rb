require "spec_helper"

RSpec.describe Lowmu::Publishers::Substack do
  let(:slug_dir) { Dir.mktmpdir("lowmu_substack") }
  let(:target_config) { {"name" => "substack", "type" => "substack"} }

  after { FileUtils.rm_rf(slug_dir) }

  describe "#publish" do
    it "raises an error with a helpful message mentioning Substack" do
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /Substack.*not yet supported/)
    end

    it "includes the path to the generated post file in the error" do
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /substack_post\.md/)
    end
  end
end
