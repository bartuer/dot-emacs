require 'optparse'

module Jcodetools
# Domain specific OptionParser extensions
module OptionHandler
  def set_banner
    self.banner = "Usage: #{$0} [options] [inputfile] [-- cmdline args]"
  end

  def handle_position(options)
    separator ""
    separator "Position options:"
    on("--line=LINE", "Current line number.") do |n|
      options[:lineno] = n.to_i
    end
    on("--column=COLUMN", "Current column number in BYTE.") do |n|
      options[:column] = n.to_i
    end
    on("-t TEST", "--test=TEST",
       "Execute test script. ",
       "TEST is TESTSCRIPT, TESTSCRIPT@TESTMETHOD, or TESTSCRIPT@LINENO.",
       "You must specify --filename option.") do |t|
      options[:test_script], options[:test_method] = t.split(/@/)
    end
    on("--filename=FILENAME", "Filename of standard input.") do |f|
      options[:filename] = f
    end
  end

  def handle_interpreter(options)
    separator ""
    separator "Interpreter options:"
    on("--fork", "Use rct-fork-client if rct-fork is running.") do 
      options[:detect_rct_fork] = true
    end
    on("--use_spec", "Use jspec.") do 
      options[:use_spec] = true
    end
  end

  def handle_misc(options)
    separator ""
    separator "Misc options:"
    on("--current_file_name=FILENAME", "Current file name.") do |f|
     options[:current_file_name] = f
    end

    on("-h", "--help", "Show this message") do
      puts self
      exit
    end
    on("-v", "--version", "Show version information") do
      puts "#{File.basename($0)} #{XMPFilter::VERSION}"
      exit
    end
  end

end

def set_extra_opts(options)
  if idx = ARGV.index("--")
    options[:options] = ARGV[idx+1..-1]
    ARGV.replace ARGV[0...idx]
  else
    options[:options] = []
  end
end

def check_opts(options)
  if options[:test_script]
    unless options[:filename]
      $stderr.puts "You must specify --filename as well as -t(--test)."
      exit 1
    end
  end
end

DEFAULT_OPTIONS = {
  :interpreter       => "rhino",
  :current_file_name => "",
  :options => ["hoge"],
  :min_codeline_size => 50,
  :width             => 79,
  :libs              => [],
  :evals             => [],
  :include_paths     => [],
  :dump              => nil,
  :wd                => nil,
  :warnings          => true,
  :use_parentheses   => true,
  :column            => nil,
  :lineno            => nil,   
  :output_stdout     => true,
  :completion        => false,
  :use_spec          => false,
  :test_script       => nil,
  :test_method       => nil,
  :detect_rct_fork   => false,
  :use_rbtest        => false,
  :detect_rbtest     => false,
  :execute_ruby_tmpfile => false,
  }
end     
