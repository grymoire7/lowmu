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
      command = Commands::Generate.new(
        slug,
        target: options[:target],
        force: options[:force],
        config: Config.load
      )

      planned = command.plan

      if planned.empty?
        if slug
          say "Output is already up-to-date. Use --force to regenerate."
        else
          say "Nothing to generate."
        end
        return
      end

      tasks = planned.map do |t|
        processing, processed = RandomProcessingTitle.generate
        {
          opts: {
            title: "#{processing} #{t[:target]} for #{t[:key]}",
            done: "#{processed} #{t[:target]} for #{t[:key]}"
          },
          block: -> { t[:generator].generate }
        }
      end

      result = ParallelTaskRunner.new(tasks).run

      if result.errors.any?
        say "\nErrors:", :red
        result.errors.each { |e| say "  #{e.title}: #{e.exception.message}", :red }
        exit(1)
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
        results.each { |entry| say "#{entry[:key]}: #{entry[:status]}" }
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
