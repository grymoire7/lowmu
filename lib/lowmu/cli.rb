module Lowmu
  class CLI < Thor
    SYMBOLS = {
      done: "✓",
      pending: "◯",
      stale: "⏱",
      not_applicable: "✗"
    }.freeze

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
    method_option :target, aliases: "-t", type: :string,
      desc: "Target type. Available: substack_long, substack_short, mastodon_short, linkedin_short, linkedin_long"
    method_option :force, aliases: "-f", type: :boolean, desc: "Force regeneration"
    method_option :recent, type: :string, desc: "Only generate for sources modified within duration (e.g. 1w, 3d)"
    def generate(slug = nil)
      command = Commands::Generate.new(
        slug,
        target: options[:target],
        force: options[:force],
        recent: options[:recent],
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

    desc "status [SLUG]", "Report generation status per target"
    method_option :all, type: :boolean, desc: "Show all inputs (default)"
    method_option :pending, type: :boolean, desc: "At least one output is pending"
    method_option :no_pending, type: :boolean, desc: "No pending outputs"
    method_option :recent, type: :string, desc: "At least one output within duration (e.g. 1w, 3d)"
    method_option :done, type: :boolean, desc: "All applicable outputs are done"
    method_option :partial, type: :boolean, desc: "Some but not all outputs are done"
    method_option :stale, type: :boolean, desc: "At least one output is stale"
    method_option :no_stale, type: :boolean, desc: "No stale outputs"
    def status(slug = nil)
      filters = {}
      filters[:pending] = true if options[:pending]
      filters[:no_pending] = true if options[:no_pending]
      filters[:done] = true if options[:done]
      filters[:partial] = true if options[:partial]
      filters[:stale] = true if options[:stale]
      filters[:no_stale] = true if options[:no_stale]
      filters[:recent] = options[:recent] if options[:recent]

      result = Commands::Status.new(slug, config: Config.load, filters: filters).call

      if result[:rows].empty?
        say "No content found."
        return
      end

      render_status_table(result)
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    desc "brainstorm", "Generate content ideas from configured sources"
    method_option :form, type: :string, default: "long", desc: "Idea form: long or short"
    method_option :num, type: :numeric, default: 5, desc: "Number of ideas to generate"
    method_option :rescan, type: :boolean, desc: "Ignore state and reprocess all source items"
    def brainstorm
      command = Commands::Brainstorm.new(
        config: Config.load,
        form: options[:form],
        num: options[:num],
        rescan: options[:rescan]
      )
      files = with_spinner("Brainstorming...") { command.call }
      say "Generated #{files.count} idea#{"s" unless files.count == 1}:"
      files.each { |f| say "  #{f}" }
    rescue Lowmu::Error => e
      error_exit(e.message)
    end

    def self.printable_commands(all = true, subcommand = false)
      super.reject { |cmd| cmd.first.match?(/\btree\b/) }
    end

    private

    def render_status_table(result)
      targets = result[:targets]
      rows = result[:rows]

      target_headers = targets.map { |t| t.sub("_", "/") }
      headers = ["input"] + target_headers

      col_widths = headers.map(&:length)
      rows.each do |row|
        col_widths[0] = [col_widths[0], row[:key].length].max
      end

      header_line = headers.each_with_index.map { |h, i| h.ljust(col_widths[i]) }.join(" | ")
      separator = col_widths.map { |w| "-" * w }.join("-+-")
      say "| #{header_line} |"
      say "+-#{separator}-+"

      rows.each do |row|
        cells = [row[:key].ljust(col_widths[0])]
        targets.each_with_index do |type, i|
          sym = SYMBOLS.fetch(row[:statuses][type], "?")
          cells << sym.center(col_widths[i + 1])
        end
        say "| #{cells.join(" | ")} |"
      end

      say ""
      say "#{SYMBOLS[:done]} done  #{SYMBOLS[:pending]} pending  #{SYMBOLS[:not_applicable]} not applicable  #{SYMBOLS[:stale]} stale"
    end

    def with_spinner(message, output: $stderr, tty: $stderr.tty?)
      if tty
        require "tty-spinner"
        spinner = TTY::Spinner.new("[:spinner] #{message}", output: output)
        spinner.auto_spin
        result = yield
        spinner.stop("done")
        result
      else
        output.puts "-> #{message}"
        yield
      end
    end

    def error_exit(message)
      say "Error: #{message}", :red
      exit(1)
    end
  end
end
