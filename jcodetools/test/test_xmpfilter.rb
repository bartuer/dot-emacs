require 'test/unit'
$: << ".." << "../lib"
require "jcodetools/xmpfilter"
require 'rubygems'
require 'mocha'

class TestXMPFilter < Test::Unit::TestCase
  include Jcodetools
  
  def setup
    @@single_re = XMPFilter::SINGLE_LINE_RE
    @@marker = XMPFilter::MARKER
    @xmp = XMPFilter.new(:interpreter=>"rhino")
  end
  
  def test_extract_data__results
    marker = XMPFilter::MARKER
    str = <<-EOF
#{marker}[1] => Fixnum 42
#{marker}[1] => Fixnum 0
#{marker}[1] ==> var
#{marker}[1] ==> var2
#{marker}[4] ==> var3
#{marker}[2] ~> some exception
#{marker}[10] => Fixnum 42
    EOF
    data = @xmp.extract_data(str)
    assert_equal([[1, [["Fixnum", "42"], ["Fixnum", "0"]]], [10, [["Fixnum", "42"]]]], data.results.sort)
  end

  def test_extract_data__exceptions
    marker = XMPFilter::MARKER
    str = <<-EOF
#{marker}[1] => Fixnum 42
#{marker}[1] => Fixnum 0
#{marker}[1] ==> var
#{marker}[1] ==> var2
#{marker}[4] ==> var3
#{marker}[2] ~> some exception
#{marker}[10] => Fixnum 42
    EOF
    data = @xmp.extract_data(str)
    assert_equal([[2, ["some exception"]]], data.exceptions.sort)
  end

  def test_extract_data__bindings
    marker = XMPFilter::MARKER
    str = <<-EOF
#{marker}[1] => Fixnum 42
#{marker}[1] => Fixnum 0
#{marker}[1] ==> var
#{marker}[1] ==> var2
#{marker}[4] ==> var3
#{marker}[2] ~> some exception
#{marker}[10] => Fixnum 42
    EOF
    data = @xmp.extract_data(str)
    assert_equal([[1, ["var", "var2"]], [4, ["var3"]]], data.bindings.sort)
  end

  def test_interpreter_command
    xmp = XMPFilter.new(:interpreter=>"rhino")
    assert_equal(%w[rhino -w], xmp.interpreter_command)
  end

  def test_add_markers
    input = File.readlines(File.join(File.dirname(__FILE__), "data/attic/add_markers-input.js"))
    output = File.readlines(File.join(File.dirname(__FILE__), "data/attic/add_markers-output.js"))
    assert_equal output.join, XMPAddMarkers.run(input.join, :min_codeline_size  => 0)
  end

  def test_single_line_re
    assert_nil "1 + 1;" =~ @@single_re
    assert_nil "// 1 + 1; //# =>" =~ @@single_re
    assert_nil "//1 + 1; //# =>" =~ @@single_re
    assert_nil "//# => " =~ @@single_re
    assert_nil "     //# => " =~ @@single_re
    assert_nil "1 + 1;//# =>" =~ @@single_re
    assert_nil "////# =>" =~ @@single_re
    assert_equal 0, "1 + 1;      //#=> " =~ @@single_re
    assert_equal 0, "1 + 1; //# =>" =~ @@single_re
  end
  
  def test_prepare_line
    input = File.readlines(File.join(File.dirname(__FILE__), "data/attic/prepare_line-input.js"))
    code = input.join
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ @xmp.prepare_line($1, idx += 1) } 
    expected = File.readlines(File.join(File.dirname(__FILE__), "data/attic/prepare_line-output.js")).join
    filtered_expect = expected.gsub(/__XMP__MARKER__/, @@marker).gsub(/\\n/,"\n")
    assert_equal filtered_expect, newcode
  end

  def test_execute
    input = File.readlines(File.join(File.dirname(__FILE__), "data/attic/execute_line_input.js")).join
    code = input.gsub(/__XMP__MARKER__/, @@marker).gsub(/\\n/,"\n")
    stdout, stderr = @xmp.execute_jsh(code)
    output = stderr.readlines
    output.each { |line|
      line.gsub!(/js> /, '');
      line.gsub!(/__JCTNEWLINE__/,"\n");
      line.gsub!(/XMP[0-9]*_[0-9]*_[0-9]*/, "__XMP__MARKER__")
    };
    assert_equal ["Rhino 1.7 release 2 2009 06 09\n", "!__XMP__MARKER__![1] => number 2\nwindow\nnavigator\nlocation\nsetTimeout\nsetInterval\nclearInterval\naddEventListener\nremoveEventListener\ndispatchEvent\nDOMDocument\nDOMNodeList\nDOMNode\nDOMElement\nXMLHttpRequest\nv\n", "!__XMP__MARKER__![2] => number 5\nwindow\nnavigator\nlocation\nsetTimeout\nsetInterval\nclearInterval\naddEventListener\nremoveEventListener\ndispatchEvent\nDOMDocument\nDOMNodeList\nDOMNode\nDOMElement\nXMLHttpRequest\nv\n", "7\n", "\n"], output
  end

  def test_extract
    input = File.readlines(File.join(File.dirname(__FILE__), "data/attic/execute_line_input.js")).join
    code = input.gsub(/__XMP__MARKER__/, @@marker).gsub(/\\n/,"\n")
    stdout, stderr = @xmp.execute_jsh(code)
    output = stderr.readlines
    output.each { |line|
      line.gsub!(/js> /, '');
      line.gsub!(/__JCTNEWLINE__/,"\n")
    };

    runtime_data = @xmp.extract_data(output)
    assert_equal [["number", "2"]], runtime_data.results[1]
    assert_equal [["number", "5"]], runtime_data.results[2]
  end

  def test_exception
    xmp = XMPFilter.new(:interpreter=>"rhino")
    input = File.readlines(File.join(File.dirname(__FILE__), "data/attic/exception_input.js")).join
    idx = 0
    code = input.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ xmp.prepare_line($1, idx += 1) }
    stdout, stderr = @xmp.execute_jsh(newcode)
    exception_output = stdout.readlines
    assert_equal "!__XMP__MARKER__![1] ~> ReferenceError: \"no_method_defined\" is not defined.__JCTNEWLINE__\n", exception_output.join.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/, "__XMP__MARKER__")
    output = stderr.readlines
    assert_equal ["Rhino 1.7 release 2 2009 06 09\n", "js> js: \"<stdin>\", line 2: exception from uncaught JavaScript throw: ReferenceError: \"no_method_defined\" is not defined.\n", "\n", "js> js> \n"], output
  end
  
  def test_annotate
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/prepare_line-input.js")).join
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ @xmp.prepare_line($1, idx += 1) } 
    stdout, stderr = @xmp.execute_jsh(newcode)
    output = stdout.readlines
    output.each { |line|
      line.gsub!(/__JCTNEWLINE__/,"\n")
    };
    runtime_data = @xmp.extract_data(output)

    idx = 0
    annotated = code.gsub(@@single_re) { |l|
      expr = $1                
      if /^\s*\/\// =~ l
        l 
      else
        @xmp.annotated_line(l, expr, runtime_data, idx += 1)
      end
    }
    annotated.gsub!(/\/\/# !>.*/, '')
    annotated.gsub!(/# (>>|~>)[^\n]*\n/m, "");
    ret = @xmp.final_decoration(annotated, output)
    assert_equal ["var test_obj = {\n", "             name: 'test' ,\n", "             age: 22,\n", "             obj:false,\n", "             a_array:[1, 2, 3],\n", "             a_function: function defun(){},\n", "             dict:{\n", "               one: 1,\n", "               two: '2',\n", "               three: 3,\n", "               four:null,\n", "               five:undefined,\n", "               six:{\n", "                 1: 'one',\n", "                 2: 'two',\n", "                 3: ['a', 1, 'b']\n", "               }\n", "               }\n", "           };\n", "\n", "test_obj                        //#=> { name:'test', age:22, obj:false, a_array:[1, 2, 3], a_function:function(){}, dict:{ one:1, two:'2', three:3, four:null, five:undefined, six:{ 1:'one', 2:'two', 3:['a', 1, 'b'] } } }\n", "3 + 4;\n"], ret
  end

  def test_run
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/prepare_line-input.js")).join
    ret = @xmp.annotate(code)
    assert_equal ["var test_obj = {\n", "             name: 'test' ,\n", "             age: 22,\n", "             obj:false,\n", "             a_array:[1, 2, 3],\n", "             a_function: function defun(){},\n", "             dict:{\n", "               one: 1,\n", "               two: '2',\n", "               three: 3,\n", "               four:null,\n", "               five:undefined,\n", "               six:{\n", "                 1: 'one',\n", "                 2: 'two',\n", "                 3: ['a', 1, 'b']\n", "               }\n", "               }\n", "           };\n", "\n", "test_obj                        //#=> { name:'test', age:22, obj:false, a_array:[1, 2, 3], a_function:function(){}, dict:{ one:1, two:'2', three:3, four:null, five:undefined, six:{ 1:'one', 2:'two', 3:['a', 1, 'b'] } } }\n", "3 + 4;\n"], ret
  end
  
  def test_loop
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/loop_input.js")).join
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ @xmp.prepare_line($1, idx += 1) } 
    stdout, stderr = @xmp.execute_jsh(newcode)
    dump = stdout.readlines
    output = []
    dump.each { |line|
      output << line.split(/__JCTNEWLINE__/)
    };
    output.flatten!

    runtime_data = @xmp.extract_data(output)
    assert_kind_of Jcodetools::XMPFilter::RuntimeData, runtime_data 
    assert_kind_of Jcodetools::XMPFilter::RuntimeData, runtime_data 
    assert_equal "#<struct Jcodetools::XMPFilter::RuntimeData results={1=>[[\"string\", \"'0'\"], [\"string\", \"'1'\"], [\"string\", \"'2'\"]]}, exceptions={}, bindings={1=>[\"i\", \"i\", \"i\"]}>", runtime_data.inspect
  end

  def test_error
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/error_input.js")).join
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ @xmp.prepare_line($1, idx += 1) } 
    stdout, stderr = @xmp.execute_jsh(newcode)
    dump = stdout.readlines
    output = []
    dump.each { |line|
      output << line.split(/__JCTNEWLINE__/)
    };
    output.flatten!

    jct_emacs_message = "/tmp/jct-emacs-message"
    jct_emacs_backtrace = "/tmp/jct-emacs-backtrace"
    jct_emacs_tmp = "/tmp/jct-emacs-tmp"
    # compress below to one line


    File.unlink jct_emacs_message if File.exist? jct_emacs_message
    File.unlink jct_emacs_backtrace if File.exist? jct_emacs_backtrace
    f = File.open(jct_emacs_tmp, "w")
    has_backtrace = false

    result = stderr.readlines
    result.grep(XMPFilter::ERROR_RE).each { |line|
      has_backtrace = true
      lineno, msg = XMPFilter::ERROR_RE.match(line).captures
      f << "-:" << lineno << ":" << msg << "\n"
    }

    has_backtrace ? File.rename(jct_emacs_tmp, jct_emacs_backtrace) : File.rename(jct_emacs_tmp, jct_emacs_message)
    expect = File.readlines(File.join(File.dirname(__FILE__), "data/attic/error_output")).join
    assert_equal "-:2: syntax error\n-:3: uncaught JavaScript runtime exception: ReferenceError: \"some\" is not defined.\n", expect
  end
  
end

