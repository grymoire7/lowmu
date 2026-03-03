require "simplecov"
SimpleCov.start do
  minimum_coverage 90
  add_filter "/spec/"
end

require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.filter_sensitive_data("<LOWMU_SUBSTACK_API_KEY>") { ENV["LOWMU_SUBSTACK_API_KEY"] }
  config.filter_sensitive_data("<LOWMU_MASTODON_ACCESS_TOKEN>") { ENV["LOWMU_MASTODON_ACCESS_TOKEN"] }
end

require "lowmu"

Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  config.warnings = true
end
