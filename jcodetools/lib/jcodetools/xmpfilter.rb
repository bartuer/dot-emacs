#!/usr/bin/env ruby
# Copyright (c) 2005-2008 Mauricio Fernandez <mfp@acm.org> http://eigenclass.org
#                         rubikitch <rubikitch@ruby-lang.org>
# Use and distribution subject to the terms of the Ruby license.

# This is needed regexps cannot match with invalid-encoding strings.
# xmpfilter is unaware of script encoding.
Encoding.default_external = "ASCII-8BIT" if RUBY_VERSION >= "1.9"

ENV['HOME'] ||= "#{ENV['HOMEDRIVE']}#{ENV['HOMEPATH']}"
require 'jcodetools/fork_config'
require 'jcodetools/compat'
require 'tmpdir'

module Jcodetools

class XMPFilter
  VERSION = "0.8.5"

  MARKER = "!XMP#{Time.new.to_i}_#{Process.pid}_#{rand(1000000)}!"
  XMP_RE = Regexp.new("^" + Regexp.escape(MARKER) + '\[([0-9]+)\] (=>|~>|==>|~=>) (.*)')
  ERROR_RE = Regexp.new("line "+ "([0-9]+):(.*error.*|.*exception.*)")
  VAR = "_xmp_#{Time.new.to_i}_#{Process.pid}_#{rand(1000000)}"
  WARNING_RE = /.*:([0-9]+): warning: (.*)/

  RuntimeData = Struct.new(:results, :exceptions, :bindings)

  INITIALIZE_OPTS = {:interpreter => "rhino", :options => [], :warnings => true, 
                     :output_stdout  => true, :use_parentheses => false}

  def windows?
    /win|mingw/ =~ RUBY_PLATFORM && /darwin/ !~ RUBY_PLATFORM
  end

  Interpreter = Struct.new(:options, :execute_method, :chdir_proc)
  INTERPRETER_JSH = Interpreter.new(["-w"],
    :execute_jsh,  nil)

  # The processor (overridable)
  def self.run(code, opts)
    new(opts).annotate(code)
  end

  def initialize(opts = {})
    options = INITIALIZE_OPTS.merge opts
    @interpreter_info = INTERPRETER_JSH
    @interpreter = options[:interpreter]
    @options = options[:options]
    @evals = options[:evals] || []
    @output_stdout = options[:output_stdout]
    @dump = options[:dump]
    @warnings = options[:warnings]
    @parentheses = options[:use_parentheses]
    @ignore_NoMethodError = options[:ignore_NoMethodError]
    test_script = options[:test_script]
    test_method = options[:test_method]
    filename = options[:filename]
    @execute_jsh_tmpfile = options[:execute_jsh_tmpfile]
    @postfix = ""
    @stdin_path = nil
    @width = options[:width]
    
    @evals << %Q!load('/Users/bartuer/etc/el/js/env.js');!
  end

  def add_markers(code, min_codeline_size = 50)
    maxlen = code.map{|x| x.size}.max
    maxlen = [min_codeline_size, maxlen + 2].max
    ret = ""
    code.each do |l|
      l = l.chomp.gsub(/ \/\/# (=>|!>).*/, "").gsub(/\s*$/, "")
      ret << (l + " " * (maxlen - l.size) + " \/\/# =>\n")
    end
    ret
  end
  
  SINGLE_LINE_RE = /^(?!(?:\s+|(?:\s*\/\/.+)?)\/\/# ?=>)(.*) \/\/# ?=>.*/
  def annotate(code)
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '')
    newcode = code.gsub(SINGLE_LINE_RE){ prepare_line($1, idx += 1) }
    File.open(@dump, "w"){|f| f.puts newcode} if @dump
    stdout, stderr = execute(newcode)

    dump = stdout.readlines
    output = []
    dump.each { |line|
      output << line.split(/__JCTNEWLINE__/)
    };
    output.flatten!             

    runtime_data = extract_data(output)
    idx = 0
    annotated = code.gsub(SINGLE_LINE_RE) { |l|
      expr = $1
      if /^\s*\/\// =~ l
        l 
      else
        annotated_line(l, expr, runtime_data, idx += 1)
      end
    }
    annotated.gsub!(/ # !>.*/, '')
    annotated.gsub!(/# (>>|~>)[^\n]*\n/m, "");
    ret = final_decoration(annotated, output)


    jct_emacs_message = "/tmp/jct-emacs-message"
    jct_emacs_backtrace = "/tmp/jct-emacs-backtrace"
    jct_emacs_tmp = "/tmp/jct-emacs-tmp"
    # compress below to one line


    File.unlink jct_emacs_message if File.exist? jct_emacs_message
    File.unlink jct_emacs_backtrace if File.exist? jct_emacs_backtrace
    f = File.open(jct_emacs_tmp, "w")
    has_backtrace = false

    result = stderr.readlines
    result.grep(ERROR_RE).each { |line|
      has_backtrace = true
      lineno, msg = ERROR_RE.match(line).captures

      f << "-:" << lineno.to_i - 1 << ":" << msg << "\n"
    }

    if (!has_backtrace) 
      dump.each { |line|
        f << line.gsub(/.*__JCTNEWLINE__.*$/, '') << "\n"
      }
    end
      
    has_backtrace ? File.rename(jct_emacs_tmp, jct_emacs_backtrace) : File.rename(jct_emacs_tmp, jct_emacs_message)
    ret
  end

  def annotated_line(line, expression, runtime_data, idx)
    "#{expression} //#=> " + (runtime_data.results[idx].map{|x| x[1]} || []).join(", ")
  end
  
  def prepare_line_annotation(expr, idx)
    XMPFilter.oneline_ize(<<-EOF).chomp
(function (context_obj){
   var uniqid;
   var value_line = '';
   var exception_line = '';
   var bind_lines = [];
   var symbol_line = '';
   var jct_introspect = function(jct_target) {
     if (jct_target === null) {
       return 'null';
     } else if (typeof jct_target === 'undefined') {
       return 'undefined';
     } else if (typeof jct_target === 'function') {
       return 'function(){}'
     } else if (typeof jct_target === 'string') {
       return '__JCTQUOTE__' + jct_target + '__JCTQUOTE__';
     } else if (jct_target.constructor === Array ||
               jct_target.toString() === '[object Object]') {
       var members = [];
       var jct_k;
       for (jct_k in jct_target) {
         if ( jct_target.hasOwnProperty(jct_k)) {
           if (jct_target.constructor === Array) {
             members.push(jct_introspect(jct_target[jct_k]));
           } else {
             members.push(jct_k + ':' + jct_introspect(jct_target[jct_k]));
           }
         }
       }
       if (jct_target.constructor === Array) {
         return '[' + members.join(', ') + ']';
       } else {
         return '{ ' + members.join(', ') + ' }';
       }
     } else {
       return jct_target.toString();
     }
   };
   (function() {
      var pn_uniqid;
      try {
        uniqid = #{expr};
        value_line = '#{MARKER}[#{idx}] => ' + (typeof uniqid) + ' ' + jct_introspect(uniqid) + '__JCTNEWLINE__';
        for (pn_uniqid in context_obj) {
          if (context_obj.hasOwnProperty(pn_uniqid) &&
              typeof pn_uniqid !== 'function') {
            bind_lines.push(pn_uniqid);
          }
        }
        for (pn_uniqid in context_obj) {
          if (context_obj.hasOwnProperty(pn_uniqid) &&
              uniqid === context_obj[pn_uniqid] &&
              pn_uniqid !== '#{expr}') {
            symbol_line = '__JCTNEWLINE__' + '#{MARKER}[#{idx}] ==> ' + pn_uniqid;
          }
        }
      } catch(e) {
        exception_line = '#{MARKER}[#{idx}] ~> ' + e.toString() + '__JCTNEWLINE__';
        throw(e);
      } finally {
        print(exception_line + value_line + bind_lines.join('__JCTNEWLINE__') +  symbol_line);
      }
    })();
 })(this);
EOF
  end
  alias_method :prepare_line, :prepare_line_annotation
  
  def safe_require_code(lib)
    oldverbose = "$#{VAR}_old_verbose"
    "#{oldverbose} = $VERBOSE; $VERBOSE = false; require '#{lib}'; $VERBOSE = #{oldverbose}"
  end
  private :safe_require_code

  def execute_jsh(code)
    meth = (windows? or @execute_jsh_tmpfile) ? :execute_tmpfile : :execute_popen
    __send__ meth, code
  end

  def execute_tmpfile(code)
    ios = %w[_ stdin stdout stderr]
    stdin, stdout, stderr = (1..3).map do |i|
      fname = if $DEBUG
                "xmpfilter.tmpfile_#{ios[i]}.js"
              else
                "xmpfilter.tmpfile_#{Process.pid}-#{i}.js"
              end
      f = File.open(fname, "w+")
      at_exit { f.close unless f.closed?; File.unlink fname unless $DEBUG}
      f
    end
    stdin.puts code
    stdin.close
    @stdin_path = File.expand_path stdin.path
    exe_line = <<-EOF.map{|l| l.strip}.join(";")
      $stdout.reopen('#{File.expand_path(stdout.path)}', 'w')
      $stderr.reopen('#{File.expand_path(stderr.path)}', 'w')
      $0 = '#{File.expand_path(stdin.path)}'
      ARGV.replace(#{@options.inspect})
      load #{File.expand_path(stdin.path).inspect}
      #{@evals.join(";")}
    EOF
    debugprint "execute command = #{(interpreter_command << "-e" << exe_line).join ' '}"

    oldpwd = Dir.pwd
    @interpreter_info.chdir_proc and @interpreter_info.chdir_proc.call
    system(*(interpreter_command << "-e" << exe_line))
    Dir.chdir oldpwd
    [stdout, stderr]
  end

  def execute_popen(code)
    require 'open3'
    stdin, stdout, stderr = Open3::popen3(*interpreter_command)
    @evals.each{|x| stdin.puts x } unless @evals.empty?
    stdin.puts code
    stdin.close
    [stdout, stderr]
  end

  def execute_script(code)
    path = File.expand_path("xmpfilter.tmpfile_#{Process.pid}.js", Dir.tmpdir)
    File.open(path, "w"){|f| f.puts code}
    at_exit { File.unlink path if File.exist? path}
    stdout_path, stderr_path = (1..2).map do |i|
      fname = "xmpfilter.tmpfile_#{Process.pid}-#{i}.js"
      File.expand_path(fname, Dir.tmpdir)
    end
    args = *(interpreter_command << %["#{path}"] << "2>" << 
      %["#{stderr_path}"] << ">" << %["#{stdout_path}"])
    system(args.join(" "))
    
    [stdout_path, stderr_path].map do |fullname|
      f = File.open(fullname, "r")
      at_exit {
        f.close unless f.closed?
        File.unlink fullname if File.exist? fullname
      }
      f
    end
  end

  def execute(code)
    __send__ @interpreter_info.execute_method, code
  end

  def interpreter_command
    r = [ @interpreter ] + @interpreter_info.options
    (r << "-").concat @options unless @options.empty?
    r
  end

  def extract_data(output)
    results = Hash.new{|h,k| h[k] = []}
    exceptions = Hash.new{|h,k| h[k] = []}
    bindings = Hash.new{|h,k| h[k] = []}
    output.grep(XMP_RE).each do |line|
      result_id, op, result = XMP_RE.match(line).captures
      case op
      when "=>"
        klass, value = /(\S+)\s+(.*)/.match(result).captures
        results[result_id.to_i] << [klass, value.gsub(/PPPROTECT/, "\n").gsub(/__JCTQUOTE__/, "'")]
      when "~>"
        exceptions[result_id.to_i] << result
      when "==>"
        bindings[result_id.to_i] << result unless result.index(VAR)
      when "~=>"
        completion_str = /(.*)/.match(result).captures
        results[result_id.to_i] << [completion_str]
      end
    end
    RuntimeData.new(results, exceptions, bindings)
  end

  def final_decoration(code, output)
    warnings = {}
    output.join.grep(WARNING_RE).map do |x|
      md = WARNING_RE.match(x)
      warnings[md[1].to_i] = md[2]
    end
    idx = 0
    ret = code.map do |line|
      w = warnings[idx+=1]
      if @warnings
        w ? (line.chomp + "// # !> #{w}") : line
      else
        line
      end
    end
    output = output.reject{|x| /^-:[0-9]+: warning/.match(x)}
    if exception = /^-e?:[0-9]+:.*|^(?!!XMP)[^\n]+:[0-9]+:in .*/m.match(output.join)
      err = exception[0]
      err.gsub!(Regexp.union(@stdin_path), '-') if @stdin_path
      ret << err.map{|line| "//# ~> " + line }
    end
    ret
  end

  def self.oneline_ize(code)
    code.gsub(/\r*\n|\r/, '')
  end

end # clas XMPFilter

class XMPAddMarkers < XMPFilter
  def self.run(code, opts)
    new(opts).add_markers(code, opts[:min_codeline_size])
  end
end

end
