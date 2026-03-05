require "spec_helper"
require "tty-spinner"

RSpec.describe Lowmu::ParallelTaskRunner do
  let(:output) { StringIO.new }

  def runner(tasks)
    described_class.new(tasks, tty: false, output: output)
  end

  describe "#run" do
    context "when all tasks succeed" do
      let(:tasks) do
        [
          {opts: {title: "Task A", done: "Done A"}, block: -> { "result_a" }},
          {opts: {title: "Task B", done: "Done B"}, block: -> { "result_b" }}
        ]
      end

      it "returns successes with block return values" do
        result = runner(tasks).run
        expect(result.successes.map(&:value)).to contain_exactly("result_a", "result_b")
      end

      it "returns no errors" do
        result = runner(tasks).run
        expect(result.errors).to be_empty
      end

      it "prints start and done messages to output" do
        runner(tasks).run
        expect(output.string).to include("-> Task A")
        expect(output.string).to include("✓ Done A")
      end
    end

    context "when one task fails" do
      let(:tasks) do
        [
          {opts: {title: "Good", done: "Done"}, block: -> { "ok" }},
          {opts: {title: "Bad", done: "Done"}, block: -> { raise "boom" }}
        ]
      end

      it "continues other tasks and captures the error" do
        result = runner(tasks).run
        expect(result.successes.size).to eq(1)
        expect(result.errors.size).to eq(1)
      end

      it "captures the exception" do
        result = runner(tasks).run
        expect(result.errors.first.exception.message).to eq("boom")
      end

      it "includes the title in the error" do
        result = runner(tasks).run
        expect(result.errors.first.title).to eq("Bad")
      end

      it "prints the error inline" do
        runner(tasks).run
        expect(output.string).to include("✗ Bad: boom")
      end
    end

    context "when all tasks fail" do
      let(:tasks) do
        [
          {opts: {title: "A", done: "done"}, block: -> { raise "err1" }},
          {opts: {title: "B", done: "done"}, block: -> { raise "err2" }}
        ]
      end

      it "returns empty successes" do
        expect(runner(tasks).run.successes).to be_empty
      end

      it "returns all errors" do
        expect(runner(tasks).run.errors.size).to eq(2)
      end
    end

    context "when tty: true" do
      let(:spinner) { instance_double(TTY::Spinner, auto_spin: nil, success: nil, error: nil) }
      let(:multi) { instance_double(TTY::Spinner::Multi) }

      before do
        allow(TTY::Spinner::Multi).to receive(:new).and_return(multi)
        allow(multi).to receive(:register).and_return(spinner)
      end

      def tty_runner(tasks)
        described_class.new(tasks, tty: true)
      end

      context "when a task succeeds" do
        let(:tasks) do
          [{opts: {title: "Task A", done: "Done A", format: :pulse}, block: -> { "x" }}]
        end

        it "returns the result as a success" do
          result = tty_runner(tasks).run
          expect(result.successes.first.value).to eq("x")
        end

        it "calls auto_spin on the spinner" do
          tty_runner(tasks).run
          expect(spinner).to have_received(:auto_spin)
        end

        it "calls success with the done message" do
          tty_runner(tasks).run
          expect(spinner).to have_received(:success).with("Done A")
        end

        it "registers the spinner with the title and extra opts" do
          tty_runner(tasks).run
          expect(multi).to have_received(:register).with("[:spinner] Task A", format: :pulse)
        end
      end

      context "when a task fails" do
        let(:tasks) do
          [{opts: {title: "Bad", done: "Done"}, block: -> { raise "boom" }}]
        end

        it "captures the error" do
          result = tty_runner(tasks).run
          expect(result.errors.first.exception.message).to eq("boom")
        end

        it "calls error with the exception message" do
          tty_runner(tasks).run
          expect(spinner).to have_received(:error).with("boom")
        end
      end
    end
  end
end
