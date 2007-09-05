require 'optparse'
require 'stringio'

module Spec
  module Runner
    class OptionParser < ::OptionParser
      class << self
        def parse(args, err, out, warn_if_no_files)
          self.new(err, out, warn_if_no_files).parse!(args)
        end

        def create_behaviour_runner(args, err, out, warn_if_no_files)
          options = parse(args, err, out, warn_if_no_files)
          # Some exit points in parse (--generate-options, --drb) don't return the options,
          # but hand over control. In that case we don't want to continue.
          return unless options
          options.create_behaviour_runner
        end
      end

      BUILT_IN_FORMATTERS = {
        'specdoc'  => Formatter::SpecdocFormatter,
        's'        => Formatter::SpecdocFormatter,
        'html'     => Formatter::HtmlFormatter,
        'h'        => Formatter::HtmlFormatter,
        'rdoc'     => Formatter::RdocFormatter,
        'r'        => Formatter::RdocFormatter,
        'progress' => Formatter::ProgressBarFormatter,
        'p'        => Formatter::ProgressBarFormatter,
        'failing_examples' => Formatter::FailingExamplesFormatter,
        'e'        => Formatter::FailingExamplesFormatter,
        'failing_behaviours' => Formatter::FailingBehavioursFormatter,
        'b'        => Formatter::FailingBehavioursFormatter
      }

      COMMAND_LINE = {
        :diff =>    ["-D", "--diff [FORMAT]", "Show diff of objects that are expected to be equal when they are not",
                                             "Builtin formats: unified|u|context|c",
                                             "You can also specify a custom differ class",
                                             "(in which case you should also specify --require)"],
        :colour =>  ["-c", "--colour", "--color", "Show coloured (red/green) output"],
        :example => ["-e", "--example [NAME|FILE_NAME]",  "Execute example(s) with matching name(s). If the argument is",
                                                          "the path to an existing file (typically generated by a previous",
                                                          "run using --format failing_examples:file.txt), then the examples",
                                                          "on each line of thatfile will be executed. If the file is empty,",
                                                          "all examples will be run (as if --example was not specified).",
                                                          " ",
                                                          "If the argument is not an existing file, then it is treated as",
                                                          "an example name directly, causing RSpec to run just the example",
                                                          "matching that name"],
        :specification => ["-s", "--specification [NAME]", "DEPRECATED - use -e instead", "(This will be removed when autotest works with -e)"],
        :line => ["-l", "--line LINE_NUMBER", Integer, "Execute behaviout or specification at given line.",
                                                       "(does not work for dynamically generated specs)"],
        :format => ["-f", "--format FORMAT[:WHERE]",  "Specifies what format to use for output. Specify WHERE to tell",
                                                    "the formatter where to write the output. All built-in formats",
                                                    "expect WHERE to be a file name, and will write to STDOUT if it's",
                                                    "not specified. The --format option may be specified several times",
                                                    "if you want several outputs",
                                                    " ",
                                                    "Builtin formats: ",
                                                    "progress|p           : Text progress",
                                                    "specdoc|s            : Example doc as text",
                                                    "rdoc|r               : Example doc as RDoc",
                                                    "html|h               : A nice HTML report",
                                                    "failing_examples|e   : Write all failing examples - input for --example",
                                                    "failing_behaviours|b : Write all failing behaviours - input for --example",
                                                    " ",
                                                    "FORMAT can also be the name of a custom formatter class",
                                                    "(in which case you should also specify --require to load it)"],
        :require => ["-r", "--require FILE", "Require FILE before running specs",
                                          "Useful for loading custom formatters or other extensions.",
                                          "If this option is used it must come before the others"],
        :backtrace => ["-b", "--backtrace", "Output full backtrace"],
        :loadby => ["-L", "--loadby STRATEGY", "Specify the strategy by which spec files should be loaded.",
                                              "STRATEGY can currently only be 'mtime' (File modification time)",
                                              "By default, spec files are loaded in alphabetical order if --loadby",
                                              "is not specified."],
        :reverse => ["-R", "--reverse", "Run examples in reverse order"],
        :timeout => ["-t", "--timeout FLOAT", "Interrupt and fail each example that doesn't complete in the",
                                              "specified time"],
        :heckle => ["-H", "--heckle CODE", "If all examples pass, this will mutate the classes and methods",
                                           "identified by CODE little by little and run all the examples again",
                                           "for each mutation. The intent is that for each mutation, at least",
                                           "one example *should* fail, and RSpec will tell you if this is not the",
                                           "case. CODE should be either Some::Module, Some::Class or",
                                           "Some::Fabulous#method}"],
        :dry_run => ["-d", "--dry-run", "Invokes formatters without executing the examples."],
        :options_file => ["-O", "--options PATH", "Read options from a file"],
        :generate_options => ["-G", "--generate-options PATH", "Generate an options file for --options"],
        :runner => ["-U", "--runner RUNNER", "Use a custom BehaviourRunner."],
        :drb => ["-X", "--drb", "Run examples via DRb. (For example against script/spec_server)"],
        :version => ["-v", "--version", "Show version"],
        :help => ["-h", "--help", "You're looking at it"]
      }

      def initialize(err, out, warn_if_no_files)
        super()
        @error_stream = err
        @out_stream = out
        @warn_if_no_files = warn_if_no_files
        @options = Options.new(@error_stream, @out_stream)
        @return_options = true
        
        @spec_parser = SpecParser.new
        @file_factory = File

        self.banner = "Usage: spec (FILE|DIRECTORY|GLOB)+ [options]"
        self.separator ""
        self.rspec_on(:diff) {|diff| @options.parse_diff(diff)}
        self.rspec_on(:colour) {@options.colour = true}
        self.rspec_on(:example) {|example| @options.parse_example(example)}
        self.rspec_on(:specification) {|example| @options.parse_example(example)}
        self.rspec_on(:line) {|line_number| @options.line_number = line_number.to_i}
        self.rspec_on(:format) {|format| @options.parse_format(format)}
        self.rspec_on(:require) {|req| @options.parse_require(req)}
        self.rspec_on(:backtrace) {@options.backtrace_tweaker = NoisyBacktraceTweaker.new}
        self.rspec_on(:loadby) {|loadby| @options.loadby = loadby}
        self.rspec_on(:reverse) {@options.reverse = true}
        self.rspec_on(:timeout) {|timeout| @options.timeout = timeout.to_f}
        self.rspec_on(:heckle) {|heckle| @options.parse_heckle(heckle)}
        self.rspec_on(:dry_run) {@options.dry_run = true}
        self.rspec_on(:options_file) do |options_file|
          parse_options_file(options_file)
          @return_options = false
        end
        self.rspec_on(:generate_options) do |options_file|
          @options.parse_generate_options(options_file, copy_original_args, @out_stream)
        end
        self.rspec_on(:runner) do |runner|
          @options.runner_arg = runner
        end
        self.rspec_on(:drb) do
          parse_drb
          @return_options = false
        end
        self.rspec_on(:version) {parse_version}
        self.on_tail(*COMMAND_LINE[:help]) {parse_help}
      end

      def parse!(args)
        @args = args
        @original_args = args.dup
        super(@args)

        return nil unless @return_options

        if @args.empty? && @warn_if_no_files
          @error_stream.puts "No files specified."
          @error_stream.puts self
          exit(6) if stderr?
        end

        if @options.line_number
          set_spec_from_line_number
        end

        if @options.formatters.empty?
          @options.formatters << Formatter::ProgressBarFormatter.new(@out_stream)
        end

        @options
      end

      protected
      def rspec_on(name, &block)
        on(*COMMAND_LINE[name], &block)
      end

      def parse_options_file(options_file)
        # Remove the --options option and the argument before writing to filecreate_behaviour_runner
        args_copy = copy_original_args
        index = args_copy.index("-O") || args_copy.index("--options")
        args_copy.delete_at(index)
        args_copy.delete_at(index)

        new_args = args_copy + IO.readlines(options_file).map {|l| l.chomp.split " "}.flatten
        return CommandLine.run(new_args, @error_stream, @out_stream, true, @warn_if_no_files)
      end

      def parse_drb
        args_copy = copy_original_args
        # Remove the --drb option
        index = args_copy.index("-X") || args_copy.index("--drb")
        args_copy.delete_at(index)

        return DrbCommandLine.run(args_copy, @error_stream, @out_stream, true, @warn_if_no_files)
      end

      def parse_version
        @out_stream.puts ::Spec::VERSION::DESCRIPTION
        exit if stdout?
      end

      def parse_help
        @out_stream.puts self
        exit if stdout?
      end      

      def set_spec_from_line_number
        if @options.examples.empty?
          if @args.length == 1
            if @file_factory.file?(@args[0])
              source = @file_factory.open(@args[0])
              example = @spec_parser.spec_name_for(source, @options.line_number)
              @options.parse_example(example)
            elsif @file_factory.directory?(@args[0])
              @error_stream.puts "You must specify one file, not a directory when using the --line option"
              exit(1) if stderr?
            else
              @error_stream.puts "#{@args[0]} does not exist"
              exit(2) if stderr?
            end
          else
            @error_stream.puts "Only one file can be specified when using the --line option: #{@args.inspect}"
            exit(3) if stderr?
          end
        else
          @error_stream.puts "You cannot use both --line and --example"
          exit(4) if stderr?
        end
      end

      def copy_original_args
        @original_args.dup
      end

      def stdout?
        @out_stream == $stdout
      end

      def stderr?
        @error_stream == $stderr
      end
    end
  end
end
