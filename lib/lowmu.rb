require "zeitwerk"
require "thor"
require "yaml"
require "fileutils"
require "ruby_llm"
require "front_matter_parser"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI")
loader.setup

module Lowmu
  class Error < StandardError; end
end
