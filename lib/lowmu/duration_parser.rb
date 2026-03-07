module Lowmu
  class DurationParser
    UNITS = {"d" => 86_400, "w" => 7 * 86_400}.freeze

    def self.parse(str)
      match = str.to_s.match(/\A(\d+)([dw])\z/)
      unless match
        raise Error, "Invalid duration #{str.inspect}. Use a number followed by d (days) or w (weeks), e.g. 3d, 1w."
      end
      match[1].to_i * UNITS[match[2]]
    end
  end
end
