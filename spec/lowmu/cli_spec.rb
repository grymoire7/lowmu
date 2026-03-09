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
    let(:runner) { instance_double(Lowmu::ParallelTaskRunner) }

    before do
      allow(Lowmu::Config).to receive(:load).and_return(config)
      allow(Lowmu::Commands::Generate).to receive(:new).and_return(command)
      allow(Lowmu::ParallelTaskRunner).to receive(:new).and_return(runner)
    end

    context "when there is nothing to generate and no slug is given" do
      before { allow(command).to receive(:plan).and_return([]) }

      it "says nothing to generate" do
        expect { cli.generate }.to output(/Nothing to generate/).to_stdout
      end
    end

    context "when there is nothing to generate and a slug is given" do
      before { allow(command).to receive(:plan).and_return([]) }

      it "tells the user the output is already up-to-date" do
        expect { cli.generate("my-post") }.to output(/already up-to-date/).to_stdout
      end

      it "mentions --force to regenerate" do
        expect { cli.generate("my-post") }.to output(/--force/).to_stdout
      end
    end

    context "when content is generated successfully" do
      let(:generator_a) { instance_double(Lowmu::Generators::MastodonShort) }
      let(:planned) do
        [{key: "posts/my-post", target: "mastodon", generator: generator_a}]
      end
      let(:success) { Lowmu::ParallelTaskRunner::TaskSuccess.new(title: "Generating mastodon...", value: "/tmp/mastodon.txt") }
      let(:run_result) { Lowmu::ParallelTaskRunner::Result.new(successes: [success], errors: []) }

      before do
        allow(command).to receive(:plan).and_return(planned)
        allow(runner).to receive(:run).and_return(run_result)
      end

      it "does not print to stdout" do
        expect { cli.generate }.not_to output.to_stdout
      end

      it "builds a runner with one task per planned item" do
        cli.generate
        expect(Lowmu::ParallelTaskRunner).to have_received(:new).with(
          [hash_including(opts: hash_including(title: /mastodon/, done: /mastodon/))]
        )
      end
    end

    context "when some tasks fail" do
      let(:error) { Lowmu::ParallelTaskRunner::TaskError.new(title: "Generating mastodon...", exception: RuntimeError.new("rate limit")) }
      let(:run_result) { Lowmu::ParallelTaskRunner::Result.new(successes: [], errors: [error]) }
      let(:planned) do
        [{key: "posts/my-post", target: "mastodon", generator: instance_double(Lowmu::Generators::MastodonShort)}]
      end

      before do
        allow(command).to receive(:plan).and_return(planned)
        allow(runner).to receive(:run).and_return(run_result)
        allow(cli).to receive(:exit)
      end

      it "prints error details to stdout" do
        expect { cli.generate }.to output(/rate limit/).to_stdout
      end

      it "exits with code 1" do
        expect { cli.generate }.to output.to_stdout
        expect(cli).to have_received(:exit).with(1)
      end
    end

    context "when Lowmu::Error is raised" do
      before do
        allow(command).to receive(:plan).and_raise(Lowmu::Error, "no config")
        allow(cli).to receive(:exit)
      end

      it "prints an error message and exits with code 1" do
        expect { cli.generate }.to output(/Error: no config/).to_stdout
        expect(cli).to have_received(:exit).with(1)
      end
    end

    context "when no slug and no --recent given" do
      before do
        allow(command).to receive(:plan).and_raise(Lowmu::Error, "Specify a slug or use --recent")
        allow(cli).to receive(:exit)
      end

      it "prints the error and exits" do
        expect { cli.generate }.to output(/Specify a slug or use --recent/).to_stdout
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
      before do
        allow(command).to receive(:call).and_return({targets: [], rows: []})
      end

      it "says no content found" do
        expect { cli.status }.to output(/No content found/).to_stdout
      end
    end

    context "when content exists" do
      before do
        allow(command).to receive(:call).and_return({
          targets: ["mastodon_short"],
          rows: [
            {key: "long/my-post", statuses: {"mastodon_short" => :done}},
            {key: "short/note", statuses: {"mastodon_short" => :pending}}
          ]
        })
      end

      it "prints the input column header" do
        expect { cli.status }.to output(/input/).to_stdout
      end

      it "prints target column headers" do
        expect { cli.status }.to output(/mastodon\/short/).to_stdout
      end

      it "prints the done symbol for done status" do
        expect { cli.status }.to output(/✓/).to_stdout
      end

      it "prints the pending symbol for pending status" do
        expect { cli.status }.to output(/◯/).to_stdout
      end

      it "prints the legend" do
        expect { cli.status }.to output(/done.*pending/m).to_stdout
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

  describe "brainstorm" do
    let(:config) do
      instance_double(Lowmu::Config,
        hugo_content_dir: Dir.mktmpdir,
        content_dir: Dir.mktmpdir,
        llm: {"model" => "claude-opus-4-6"},
        persona: "I write about software.",
        sources: [])
    end

    around do |example|
      suppress_output { example.run }
    end

    before do
      allow(Lowmu::Config).to receive(:load).and_return(config)
    end

    it "reports the number of generated ideas" do
      allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
        instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md", "long-idea-two.md"])
      )
      expect { Lowmu::CLI.start(["brainstorm"]) }.to output(/Generated 2 ideas/).to_stdout
    end

    it "uses singular when one idea is generated" do
      allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
        instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md"])
      )
      expect { Lowmu::CLI.start(["brainstorm"]) }.to output(/Generated 1 idea\b/).to_stdout
    end

    it "lists the generated filenames" do
      allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
        instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md"])
      )
      expect { Lowmu::CLI.start(["brainstorm"]) }.to output(/long-idea-one\.md/).to_stdout
    end

    it "passes --form to the command" do
      cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: ["short-idea.md"])
      expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(form: "short")).and_return(cmd_double)
      Lowmu::CLI.start(["brainstorm", "--form", "short"])
    end

    it "passes --num to the command" do
      cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: [])
      expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(num: 3)).and_return(cmd_double)
      Lowmu::CLI.start(["brainstorm", "--num", "3"])
    end

    it "passes --rescan to the command" do
      cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: [])
      expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(rescan: true)).and_return(cmd_double)
      Lowmu::CLI.start(["brainstorm", "--rescan"])
    end

    it "passes --recent to the brainstorm command" do
      cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: [])
      expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(recent: "7d")).and_return(cmd_double)
      Lowmu::CLI.start(["brainstorm", "--recent", "7d"])
    end

    it "passes --per-source to the brainstorm command" do
      cmd_double = instance_double(Lowmu::Commands::Brainstorm, call: [])
      expect(Lowmu::Commands::Brainstorm).to receive(:new).with(hash_including(per_source: 5)).and_return(cmd_double)
      Lowmu::CLI.start(["brainstorm", "--per-source", "5"])
    end

    it "prints an error on Lowmu::Error" do
      allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
        instance_double(Lowmu::Commands::Brainstorm, call: nil).tap do |d|
          allow(d).to receive(:call).and_raise(Lowmu::Error, "No new source items found.")
        end
      )
      expect { Lowmu::CLI.start(["brainstorm"]) }.to output(/No new source items found/).to_stdout.and raise_error(SystemExit)
    end

    it "reports progress to stderr while running" do
      allow(Lowmu::Commands::Brainstorm).to receive(:new).and_return(
        instance_double(Lowmu::Commands::Brainstorm, call: ["long-idea-one.md"])
      )
      expect { Lowmu::CLI.start(["brainstorm"]) }.to output(/Brainstorming/).to_stderr
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
