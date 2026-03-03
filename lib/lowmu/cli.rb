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

    desc "new MD_PATH HERO_IMAGE_PATH", "Register a new post for publishing"
    def new(md_path, hero_image_path)
      result = Commands::New.new(md_path, hero_image_path, config: Config.load).call
      say "Created slug: #{result[:slug]}"
      say "Targets: #{result[:targets].join(", ")}"
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "generate SLUG", "Generate platform-specific content for a slug"
    method_option :target, aliases: "-t", type: :string, desc: "Specific target (default: all)"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force regeneration of existing content"
    def generate(slug)
      results = Commands::Generate.new(
        slug,
        target: options[:target],
        force: options[:force],
        config: Config.load
      ).call
      results.each { |r| say "Generated #{r[:target]}: #{r[:file]}" }
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "status [SLUG]", "Report publishing status"
    def status(slug = nil)
      results = Commands::Status.new(slug, config: Config.load).call
      results.each do |entry|
        say "\n#{entry[:slug]}:"
        entry[:targets].each do |target, data|
          say "  #{target}: #{data["status"]}"
        end
      end
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "publish SLUG", "Publish generated content to configured targets"
    method_option :target, aliases: "-t", type: :string, desc: "Specific target (default: all)"
    def publish(slug)
      results = Commands::Publish.new(
        slug,
        target: options[:target],
        config: Config.load
      ).call
      results.each do |r|
        if r[:status] == :manual
          say "LinkedIn: copy-paste ready at #{r[:file]}"
        else
          say "Published #{r[:target]}"
        end
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
