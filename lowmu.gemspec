require_relative "lib/lowmu/version"

Gem::Specification.new do |spec|
  spec.name = "lowmu"
  spec.version = Lowmu::VERSION
  spec.authors = ["Tracy Atteberry"]
  spec.summary = "Low friction publishing tool for blog posts and social web content"
  spec.required_ruby_version = ">= 3.4.0"
  spec.files = Dir["lib/**/*", "exe/**/*"]
  spec.bindir = "exe"
  spec.executables = ["lowmu"]

  spec.add_dependency "thor", "~> 1.5"
  spec.add_dependency "ruby_llm", "~> 1.12"
  spec.add_dependency "zeitwerk", "~> 2.7"
  spec.add_dependency "front_matter_parser", "~> 1.0"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "rss", "~> 0.3"
end
