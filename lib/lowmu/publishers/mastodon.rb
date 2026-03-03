require "net/http"
require "json"

module Lowmu
  module Publishers
    class Mastodon < Base
      def publish
        content = File.read(generated_file_path(Generators::Mastodon::OUTPUT_FILE))
        response = post_status(content)

        unless response.code == "200"
          raise Error, "Mastodon API error (#{response.code}): #{response.body}"
        end

        JSON.parse(response.body)["url"]
      end

      private

      def post_status(content)
        uri = URI("#{base_url}/api/v1/statuses")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate({"status" => content})

        http.request(request)
      end

      def base_url
        @target_config["base_url"]
      end

      def access_token
        ENV.fetch("LOWMU_MASTODON_ACCESS_TOKEN", nil) ||
          @target_config.dig("auth", "access_token") ||
          raise(Error, "Mastodon access token not configured")
      end
    end
  end
end
