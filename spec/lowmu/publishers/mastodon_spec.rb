require "spec_helper"

RSpec.describe Lowmu::Publishers::Mastodon do
  let(:slug_dir) { Dir.mktmpdir("lowmu_mastodon") }
  let(:target_config) do
    {
      "name" => "mastodon",
      "type" => "mastodon",
      "base_url" => "https://mastodon.social",
      "auth" => {"access_token" => "test_token"}
    }
  end

  after { FileUtils.rm_rf(slug_dir) }

  before do
    File.write(File.join(slug_dir, "mastodon.txt"), "Test post #ruby [URL]")
  end

  describe "#publish" do
    context "with a successful API response" do
      before do
        stub_request(:post, "https://mastodon.social/api/v1/statuses")
          .to_return(
            status: 200,
            body: JSON.generate({"url" => "https://mastodon.social/@user/123"}),
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "returns the URL of the published post" do
        result = described_class.new(slug_dir, target_config).publish
        expect(result).to eq("https://mastodon.social/@user/123")
      end

      it "sends the post content in the request body" do
        described_class.new(slug_dir, target_config).publish
        expect(WebMock).to have_requested(:post, "https://mastodon.social/api/v1/statuses")
          .with(body: hash_including("status" => "Test post #ruby [URL]"))
      end
    end

    context "with an API error" do
      before do
        stub_request(:post, "https://mastodon.social/api/v1/statuses")
          .to_return(status: 401, body: "Unauthorized")
      end

      it "raises an error" do
        expect { described_class.new(slug_dir, target_config).publish }
          .to raise_error(Lowmu::Error, /Mastodon API error/)
      end
    end

    it "raises if mastodon.txt has not been generated" do
      FileUtils.rm(File.join(slug_dir, "mastodon.txt"))
      expect { described_class.new(slug_dir, target_config).publish }
        .to raise_error(Lowmu::Error, /not found/)
    end
  end
end
