module Lowmu
  class ParallelTaskRunner
    Result = Struct.new(:successes, :errors, keyword_init: true)
    TaskSuccess = Struct.new(:title, :value, keyword_init: true)
    TaskError = Struct.new(:title, :exception, keyword_init: true)

    def initialize(tasks, tty: $stderr.tty?, output: $stderr)
      @tasks = tasks
      @tty = tty
      @output = output
    end

    def run
      if @tty
        run_with_spinners
      else
        run_plain
      end
    end

    private

    def run_plain
      successes = []
      errors = []
      mutex = Mutex.new

      threads = @tasks.map do |task|
        opts = task[:opts].dup
        title = opts.delete(:title) || "Running..."
        done = opts.delete(:done) || "Done"
        block = task[:block]

        @output.puts "-> #{title}"

        Thread.new do
          value = block.call
          mutex.synchronize do
            @output.puts "✓ #{done}"
            successes << TaskSuccess.new(title: title, value: value)
          end
        rescue => e
          mutex.synchronize do
            @output.puts "✗ #{title}: #{e.message}"
            errors << TaskError.new(title: title, exception: e)
          end
        end
      end

      threads.each(&:join)
      Result.new(successes: successes, errors: errors)
    end

    def run_with_spinners
      # implemented in Task 3
      raise NotImplementedError
    end
  end
end
