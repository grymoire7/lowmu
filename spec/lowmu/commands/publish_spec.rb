require "spec_helper"

RSpec.describe Lowmu::Commands::Publish do
  let(:base_dir) { Dir.mktmpdir("lowmu_test") }
  let(:slug) { "my-post" }
  let(:slug_dir) { File.join(base_dir, slug) }

  let(:hugo_target) { {"name" => "tracyatteberry", "type" => "hugo", "base_path" => base_dir} }
  let(:linkedin_target) { {"name" => "linkedin", "type" => "linkedin"} }

  let(:config) do
    instance_double(Lowmu::Config, content_dir: base_dir)
  end

  before do
    FileUtils.mkdir_p(slug_dir)
    File.write(File.join(slug_dir, "hugo.md"), "# Hugo post")
    File.write(File.join(slug_dir, "hero_image.jpg"), "fake image")
    File.write(File.join(slug_dir, "linkedin.md"), "LinkedIn post content")

    store = Lowmu::ContentStore.new(base_dir)
    store.write_status(slug, {
      "tracyatteberry" => {"status" => "generated"},
      "linkedin" => {"status" => "generated"}
    })

    allow(config).to receive(:target_config).with("tracyatteberry").and_return(hugo_target)
    allow(config).to receive(:target_config).with("linkedin").and_return(linkedin_target)
  end

  after { FileUtils.rm_rf(base_dir) }

  describe "#call" do
    it "publishes all generated targets" do
      results = described_class.new(slug, config: config).call
      expect(results.map { |r| r[:target] }).to contain_exactly("tracyatteberry", "linkedin")
    end

    it "updates status to published for each target" do
      described_class.new(slug, config: config).call
      store = Lowmu::ContentStore.new(base_dir)
      expect(store.read_status(slug).dig("tracyatteberry", "status")).to eq("published")
    end

    it "marks LinkedIn as manual with the file path" do
      results = described_class.new(slug, config: config).call
      linkedin_result = results.find { |r| r[:target] == "linkedin" }
      expect(linkedin_result[:status]).to eq(:manual)
      expect(linkedin_result[:file]).to include("linkedin.md")
    end

    it "raises for a target not in generated state" do
      store = Lowmu::ContentStore.new(base_dir)
      store.update_target_status(slug, "tracyatteberry", {"status" => "pending"})
      expect {
        described_class.new(slug, target: "tracyatteberry", config: config).call
      }.to raise_error(Lowmu::Error, /not in.*generated/)
    end

    it "raises if the slug does not exist" do
      expect {
        described_class.new("nonexistent", config: config).call
      }.to raise_error(Lowmu::Error, /not found/)
    end
  end
end
