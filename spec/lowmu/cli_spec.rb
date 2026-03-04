require "spec_helper"

RSpec.describe Lowmu::CLI do
  subject(:cli) { described_class.new([], {}, {}) }

  describe ".exit_on_failure?" do
    it "returns true" do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe "#configure" do
    let(:command) { instance_double(Lowmu::Commands::Configure) }

    before do
      allow(Lowmu::Commands::Configure).to receive(:new).and_return(command)
    end

    context "when the config is created" do
      before { allow(command).to receive(:call).and_return({created: true, path: "/tmp/config.yml"}) }

      it "reports the new config path" do
        expect { cli.configure }.to output(/Config created at \/tmp\/config\.yml/).to_stdout
      end
    end

    context "when the config already exists" do
      before { allow(command).to receive(:call).and_return({exists: true, path: "/tmp/config.yml"}) }

      it "reports the existing config path" do
        expect { cli.configure }.to output(/Config already exists at \/tmp\/config\.yml/).to_stdout
      end
    end

    context "when Lowmu::Error is raised" do
      before do
        allow(command).to receive(:call).and_raise(Lowmu::Error, "disk full")
        allow(cli).to receive(:exit)
      end

      it "prints an error message and exits with code 1" do
        expect { cli.configure }.to output(/Error: disk full/).to_stdout
        expect(cli).to have_received(:exit).with(1)
      end
    end
  end

  describe "#generate" do
    let(:command) { instance_double(Lowmu::Commands::Generate) }
    let(:config) { instance_double(Lowmu::Config) }

    before do
      allow(Lowmu::Config).to receive(:load).and_return(config)
      allow(Lowmu::Commands::Generate).to receive(:new).and_return(command)
    end

    context "when there is nothing to generate and no slug is given" do
      before { allow(command).to receive(:call).and_return([]) }

      it "says nothing to generate" do
        expect { cli.generate }.to output(/Nothing to generate/).to_stdout
      end
    end

    context "when there is nothing to generate and a slug is given" do
      before { allow(command).to receive(:call).and_return([]) }

      it "produces no output" do
        expect { cli.generate("my-post") }.not_to output.to_stdout
      end
    end

    context "when content is generated" do
      before do
        allow(command).to receive(:call).and_return([
          {key: "posts/my-post", target: "mastodon", file: "/tmp/lowmu/posts/my-post/mastodon.txt"},
          {key: "posts/my-post", target: "linkedin-post", file: "/tmp/lowmu/posts/my-post/linkedin_post.md"}
        ])
      end

      it "reports each generated result" do
        expect { cli.generate }.to output(
          /Generated mastodon for posts\/my-post.*Generated linkedin-post for posts\/my-post/m
        ).to_stdout
      end
    end

    context "when Lowmu::Error is raised" do
      before do
        allow(command).to receive(:call).and_raise(Lowmu::Error, "no config")
        allow(cli).to receive(:exit)
      end

      it "prints an error message and exits with code 1" do
        expect { cli.generate }.to output(/Error: no config/).to_stdout
        expect(cli).to have_received(:exit).with(1)
      end
    end
  end

  describe "#status" do
    let(:command) { instance_double(Lowmu::Commands::Status) }
    let(:config) { instance_double(Lowmu::Config) }

    before do
      allow(Lowmu::Config).to receive(:load).and_return(config)
      allow(Lowmu::Commands::Status).to receive(:new).and_return(command)
    end

    context "when no content is found" do
      before { allow(command).to receive(:call).and_return([]) }

      it "says no content found" do
        expect { cli.status }.to output(/No content found/).to_stdout
      end
    end

    context "when content exists" do
      before do
        allow(command).to receive(:call).and_return([
          {key: "posts/my-post", status: :pending},
          {key: "notes/other-note", status: :generated}
        ])
      end

      it "prints each key with its status" do
        expect { cli.status }.to output(
          /posts\/my-post: pending.*notes\/other-note: generated/m
        ).to_stdout
      end
    end

    context "when Lowmu::Error is raised" do
      before do
        allow(command).to receive(:call).and_raise(Lowmu::Error, "cannot load config")
        allow(cli).to receive(:exit)
      end

      it "prints an error message and exits with code 1" do
        expect { cli.status }.to output(/Error: cannot load config/).to_stdout
        expect(cli).to have_received(:exit).with(1)
      end
    end
  end

  describe ".printable_commands" do
    it "does not list the tree command" do
      cmd_names = described_class.printable_commands.map(&:first)
      expect(cmd_names).not_to include(match(/\btree\b/))
    end

    it "does not list a new command" do
      cmd_names = described_class.printable_commands.map(&:first)
      expect(cmd_names).not_to include(match(/\bnew\b/))
    end

    it "does not list a publish command" do
      cmd_names = described_class.printable_commands.map(&:first)
      expect(cmd_names).not_to include(match(/\bpublish\b/))
    end
  end
end
