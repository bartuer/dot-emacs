# Copyright (c) 2005-2009 Mauricio Fernandez <mfp@acm.org> http://eigenclass.org
#                         rubikitch <rubikitch@ruby-lang.org>
# Use and distribution subject to the terms of the Ruby license.
require 'jcodetools/xmpfilter'
require "jcodetools/xmpjspecfilter"
require 'rubygems'
require 'ruby-debug' ; Debugger.start

module Jcodetools

  class XMPCompleteFilter < XMPFilter
    INTERPRETER_COMPLETE = Interpreter.new(["-w"], :execute_complete, nil)

    # [[file:~/local/src/rails/actionpack/lib/action_view/helpers/javascript_helper.rb::javascript%20gsub%20r%20n%20n%20r%20JS_ESCAPE_MAP%201][escape]]
    JS_ESCAPE_MAP = {
        '\\'    => '\\\\',
        '</'    => '<\/',
        "\r\n"  => '\n',
        "\n"    => '\n',
        "\r"    => '\n',
        '"'     => '\\"',
        "'"     => "\\'" }

    def initialize(opts = {})
      super
      @interpreter_info = INTERPRETER_COMPLETE
      @use_spec = opts[:use_spec]
      jct_completion_debug = '/tmp/jct_completion_debug'
      File.unlink jct_completion_debug if File.exist? jct_completion_debug
      @debuglog = File.open(jct_completion_debug, "w")
    end

    def self.run(code, opts)
      new(opts).completion_code(code, opts[:lineno], opts[:column])
    end

    def prepare_code(code)
      escaped_code = code.gsub(/(["])/) { JS_ESCAPE_MAP[$1] }
      wraped_code  = @use_spec?  Jcodetools::XMPJSpecFilter.jspec_wrap(escaped_code) : escaped_code
      wraped_code.gsub!(/__JCT_NEWLINE__/, '\n').gsub!(/__JCT_FUNC_PARAMETERS_RE__/, 'function *[a-zA-Z0-9_]*(\(.*\)) *\{')
      send_to_shell_code = Jcodetools::XMPFilter.oneline_ize(wraped_code).chomp
      @debuglog << "SEND_TO_JSHELL: " << "\n\n"
      @debuglog << send_to_shell_code
      send_to_shell_code
    end
    
    def execute_complete(code)
      require 'open3'
      stdin, stdout, stderr = Open3::popen3(*interpreter_command)
      @evals.each{|x| stdin.puts x } unless @evals.empty? # load(env.js)
      stdin.puts(prepare_code(code))
      stdin.close
      [stdout, stderr]
    end

    def prepare_line(line, column)
      expr = line.gsub(/^(\w*)\.$/, '\1')
      @debuglog << "LINE: " << line << "\n"
      @debuglog << "EXPR: " << expr << "\n"
      if (expr)
        idx = 1
        Jcodetools::XMPFilter.oneline_ize(<<EOC).chomp
(function(jct_target) {
  var members = [];
  var jct_k;
  for (jct_k in jct_target) {
    var o = jct_target[jct_k];
    if (o === null) {
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + ':null' + '|' + jct_k);
    } else if (o.constructor === Array) {
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + '[' + o.length + ']' + '|' + jct_k);
    } else if (o.toString() === '[object Object]') {
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + '{ }' + '|' + jct_k);
    } else if (typeof o === 'function') {
      var a = o.toString().split('__JCT_NEWLINE__');
      var sig = jct_k + a[1].replace(/__JCT_FUNC_PARAMETERS_RE__/g, '$1');
      members.push('#{MARKER}[#{idx}] ~=> ' + sig + '|' + sig);
    } else if (typeof o === 'string'){
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + ' str: ' + o +  '|' + jct_k);
    } else if (typeof o === 'number'){
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + ' num: ' +  o +  '|' + jct_k);
    } else if (typeof o === 'boolean'){
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + ' boolean: ' + o +  '|' + jct_k);
    } else {
      members.push('#{MARKER}[#{idx}] ~=> ' + jct_k + '|' + jct_k);
    }
  }
  print(members.join('__JCT_NEWLINE__'));
})(#{expr});
EOC
      end
    end

    def completion_code(code, lineno, column=nil)
      newcode = []
      code.to_a.each_with_index{|line, i|
        if i+1 == lineno
          newcode.push(prepare_line(line.chomp, nil))
        else
          newcode.push(line.gsub(/\/\/#=>.*$/,';'))
        end
      }
      stdout, stderr = execute_complete(newcode.join)
      output = stdout.readlines
      runtime_data = extract_data(output)
      debugger
      dat = runtime_data.results[1]
      dat.join('__JCT_NEWLINE__')
    end
    
  end
end

