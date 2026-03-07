module Lowmu
  module Generators
    def self.registry
      @registry ||= {
        "substack_long" => SubstackLong,
        "substack_short" => SubstackShort,
        "mastodon_short" => MastodonShort,
        "linkedin_short" => LinkedinShort,
        "linkedin_long" => LinkedinLong
      }.freeze
    end
  end
end
