# Copyright (c) 2005-2009 Mauricio Fernandez <mfp@acm.org> http://eigenclass.org
#                         rubikitch <rubikitch@ruby-lang.org>
# Use and distribution subject to the terms of the Ruby license.
require 'jcodetools/xmpfilter'

# [[file:~/local/src/jspec/lib/jspec.js::have_length_within%20actual%20length%20expected%200%20actual%20length%20last%20expected][matcher]]

module Jcodetools

  
FLOAT_TOLERANCE = 0.0001
  class XMPJSpecFilter < XMPFilter
    INTERPRETER_JSPEC = Interpreter.new(["-w"], :execute_jspec, nil)
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
      @interpreter_info = INTERPRETER_JSPEC
    end

    def self.jspec_wrap(code)
      XMPFilter.oneline_ize(<<-EOF).chomp
load('/Users/bartuer/local/src/jspec/lib/jspec.js');
(function (jspec_wrap_context){
eval('with (JSpec){' + "#{code}" + '}');
return jspec_wrap_context;
})(JSpec)
.run({ formatter : JSpec.formatters.Terminal, failuresOnly : true } )
.report();
EOF
    end


    def execute_jspec(code)
      require 'open3'
      stdin, stdout, stderr = Open3::popen3(*interpreter_command)
      @evals.each{|x| stdin.puts x } unless @evals.empty? # load(env.js)
      escaped_code = code.gsub(/(["])/) { JS_ESCAPE_MAP[$1] }
      stdin.puts XMPJSpecFilter.jspec_wrap(escaped_code)
      stdin.close
      [stdout, stderr]
    end

    private
    def annotated_line(line, expression, runtime_data, idx)
      indent =  /^\s*/.match(line)[0]
      assertions(expression.strip, runtime_data, idx).map{|x| indent + x}.join("\n")
    end


    def assertions(expression, runtime_data, index)
      exceptions = runtime_data.exceptions
      ret = []

      unless (vars = runtime_data.bindings[index]).empty?
        vars.each{|var| ret << equal_assertion(var, expression) }
      end
      if !(wanted = runtime_data.results[index]).empty? || !exceptions[index]
        case wanted.size
        when 1
          ret.concat _value_assertions(wanted[0], expression)
        else
          # discard values from multiple runs
          ret.concat(["#jxmpfilter: WARNING!! extra values ignored"] + 
                     _value_assertions(wanted[0], expression))
        end
      else
        ret.concat raise_assertion(expression, exceptions, index)
      end
      ret
    end

    def _value_assertions(klass_value_txt_pair, expression)
      klass_txt, value_txt = klass_value_txt_pair
      value_assertions klass_txt, value_txt, expression
    end

    def raise_assertion(expression, exceptions, index)
      ["expect(function(){#{expression}}).to(throw_error, '#{exceptions[index][0]}');"]
    end

    def true_assertion(actual)
      ["expect(#{actual}).to(be_true);"]
    end

    def false_assertion(actual)
      ["expect(#{actual}).to(be_false);"]
    end

    def value_assertions(klass_txt, value_txt, expression)
      case klass_txt
      when "boolean"
        if value_txt == "true"
          true_assertion expression
        else
          false_assertion expression
        end
      when "number"
        ["expect(#{expression}).to(be, #{value_txt});"]
      when "function"
        ["expect(#{expression}).to(be_type, '#{klass_txt}');"]
      when "string"
        ["expect(#{expression}).to(be, #{value_txt});"]
      else
        expect_item = ["expect(#{expression}).to(be_type, '#{klass_txt}');"]
        if value_txt == "null"
          expect_item.push("expect(#{expression}).to(be_null);")
        else
          expect_item.push("expect(#{expression}).to(eql, #{value_txt});")
        end
        expect_item
      end
    end

    def equal_assertion(expected, actual)
      ["expect(#{actual}).to(be, #{expected});"]
    end

  end
end
