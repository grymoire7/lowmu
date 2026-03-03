require "spec_helper"

RSpec.describe Lowmu::CLI do
  describe ".printable_commands" do
    it "does not list the tree command" do
      cmd_names = described_class.printable_commands.map(&:first)
      expect(cmd_names).not_to include(match(/tree/))
    end
  end
end
