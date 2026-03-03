module Lowmu
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "configure", "Create or update the configuration file"
    def configure
      result = Commands::Configure.new.call
      if result[:created]
        say "Config created at #{result[:path]}"
      else
        say "Config already exists at #{result[:path]}"
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "generate [SLUG]", "Generate platform content from Hugo source"
    method_option :target, aliases: "-t", type: :string, desc: "Specific target (default: all)"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force regeneration"
    def generate(slug = nil)
      results = Commands::Generate.new(
        slug,
        target: options[:target],
        force: options[:force],
        config: Config.load
      ).call
      if results.empty?
        say "Nothing to generate." unless slug
      else
        results.each { |r| say "Generated #{r[:target]} for #{r[:slug]}: #{r[:file]}" }
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "status [SLUG]", "Report generation status"
    def status(slug = nil)
      results = Commands::Status.new(slug, config: Config.load).call
      if results.empty?
        say "No content found."
      else
        results.each { |entry| say "#{entry[:slug]}: #{entry[:status]}" }
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    def self.printable_commands(all = true, subcommand = false)
      super.reject { |cmd| cmd.first.match?(/\btree\b/) }
    end

    private

    def error_exit(message)
      say "Error: #{message}", :red
      exit(1)
    end
  end
end
