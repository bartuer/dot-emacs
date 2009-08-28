require 'test/unit'
$: << ".." << "../lib"
require "jcodetools/xmpjspecfilter"

class TestXMPJSPECFilter < Test::Unit::TestCase
  include Jcodetools

  def setup
    @@single_re = XMPJSpecFilter::SINGLE_LINE_RE
  end

  def test_types
    xmp = XMPJSpecFilter.new
    input = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_read_to_evalued.js")).join
    expected = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_evalued.js")).join
    output = xmp.annotate(input)
    assert_equal expected, output.join
  end
  
  def test_catch_exception
    xmp = XMPJSpecFilter.new
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_throw.js")).join
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ xmp.prepare_line_annotation($1, idx += 1) }
    stdout, stderr = xmp.execute_jspec(newcode)
    output = stdout.readlines
    runtime_data = xmp.extract_data(output)
    assert_kind_of Jcodetools::XMPFilter::RuntimeData, runtime_data 
    assert_equal "#<struct Jcodetools::XMPFilter::RuntimeData results={}, exceptions={1=>[\"ReferenceError: \\\"no_name_method\\\" is not defined.__JCTNEWLINE__\"]}, bindings={}>", runtime_data.inspect
  end
  
  def test_raise_assertion
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_throw.js")).join
    xmp = XMPJSpecFilter.new
    newcode = xmp.annotate(code)
    assert_equal [" /*jslint\n", "  */\n", "\n", "JSpec.describe(\n", "  'Dashtry',\n", "\n", "  function () {\n", "    before_each(\n", "      function () {\n", "      });\n", "\n", "    describe\n", "    ('undefined',\n", "     function () {\n", "       it\n", "       ('should success',\n", "        function () {\n", "          expect(function(){no_name_method();}).to(throw_error, 'ReferenceError: \"no_name_method\" is not defined.');\n", "        });\n", "     });\n", "  });\n", "\n", "\n"], newcode
  end

  def test_assert_simple
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_input.js")).join
    xmp = XMPJSpecFilter.new
    assert_equal [" /*jslint\n", "  */\n", "\n", "JSpec.describe(\n", "  'Dashtry',\n", "\n", "  function () {\n", "    before_each(\n", "      function () {\n", "      });\n", "\n", "    describe\n", "    ('a success test',\n", "    function () {\n", "       it\n", "       ('should success',\n", "        function () {\n", "          expect(true).to(be_true);\n", "        });\n", "    });\n", "  });\n", "\n", "\n"], newcode = xmp.annotate(code)
  end

  def test_wrap
    xmp = XMPJSpecFilter.new
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_input.js")).join
    idx = 0
    code = code.gsub(/\/\/# !>.*/, '') 
    newcode = code.gsub(@@single_re){ xmp.prepare_line_annotation($1, idx += 1) }
    stdout, stderr = xmp.execute_jspec(newcode)
    assert_equal "!__XMP__MARKR__![1] => boolean true version suites allSuites matchers stats options defaultContext formatters Assertion ProxyAssertion Suite Spec DSLs findSuite shareBehaviorsOf copySpecs argumentsToArray color defaultMatcherMessage normalizeMatcherMessage normalizeMatcherBody option hash last puts escape does expect strip callIterator extend each inject map any select addMatchers addMatcher describe contentsOf evalBody preprocess range whenFinished report run whenCurrentSpecIsFinished runSuite fail runSpec requires query error post reportToServer xhr hasXhr load exec currentSuite currentSpec\n", stdout.readlines[0].gsub!(/XMP[0-9]*_[0-9]*_[0-9]*/, "__XMP__MARKR__").gsub!(/__JCTNEWLINE__/," ")
  end

  
end
