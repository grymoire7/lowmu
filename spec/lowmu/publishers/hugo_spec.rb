require "spec_helper"

RSpec.describe Lowmu::Publishers::Hugo do
  let(:slug_dir) { Dir.mktmpdir("lowmu_slug") }
  let(:hugo_base) { Dir.mktmpdir("lowmu_hugo") }
  let(:target_config) do
    {"name" => "tracyatteberry", "type" => "hugo", "base_path" => hugo_base}
  end

  after do
    FileUtils.rm_rf(slug_dir)
    FileUtils.rm_rf(hugo_base)
  end

  before do
    File.write(File.join(slug_dir, "hugo.md"), "# Generated Hugo post")
    File.write(File.join(slug_dir, "hero_image.jpg"), "fake image")
  end

  describe "#publish" do
    subject(:dest_dir) { described_class.new(slug_dir, target_config).publish }

    it "returns the destination directory path" do
      expect(dest_dir).to be_a(String)
      expect(Dir.exist?(dest_dir)).to be true
    end

    it "copies hugo.md to the destination as index.md" do
      dest_dir
      expect(File.exist?(File.join(dest_dir, "index.md"))).to be true
    end

    it "copies the hero image to the destination" do
      dest_dir
      expect(File.exist?(File.join(dest_dir, "hero_image.jpg"))).to be true
    end

    it "raises if hugo.md has not been generated" do
      FileUtils.rm(File.join(slug_dir, "hugo.md"))
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /not found/)
    end
  end
end
