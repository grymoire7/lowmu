require "spec_helper"

RSpec.describe Lowmu::CLI do
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
