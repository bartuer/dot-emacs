require 'test/unit'
$: << ".." << "../lib"
require "jcodetools/xmpcompletefilter"

class TestXMPCompleteFilter < Test::Unit::TestCase
  include Jcodetools

  def setup

  end

  def test_prepare_line
    xmp = XMPCompleteFilter.new(:use_spec => false)
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_complete.js"))
    newcode = []
    code.to_a.each_with_index{|line, i|
      if i+1 == 10
        newcode.push(xmp.prepare_line(line.chomp, nil))
      else
        newcode.push(line)
      end
    }
    before_exec_code = newcode.join.gsub(/__JCT_FUNC_PARAMETERS_RE__/, '\n*function *[a-zA-Z0-9_]*(\(.*\)) *\{[.\n]*\}\n*')
    before_exec_code.gsub!(/__JCT_NEWLINE__/, '\n')
    assert_equal "var test_obj = {\n  p: defun ,\n  place: cook,\n  a: [1,2,3] ,\n  d: {one:1,\n  two: '2'\n  },\n  b:false\n};\n(function(jct_target) {  var members = [];  var jct_k;  for (jct_k in jct_target) {    if (jct_target[jct_k].constructor === Array) {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '[]' + '|' + jct_k);    } else if (jct_target[jct_k].toString() === '[object Object]') {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '{}' + '|' + jct_k);    } else if (typeof jct_target[jct_k] === 'function') {      var function_introspection = jct_target[jct_k].toString();      var sig = jct_k + function_introspection.replace(/\\n*function *[a-zA-Z0-9_]*(\\(.*\\)) *\\{[.\\n]*\\}\\n*/gm, '$1');      members.push('!__XMP_MARKER__![1] ~=> ' + sig + '|' + sig);    } else {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '|' + jct_k);    }  }  print(members.join('\\n'));})(test_obj);function defun(name, len, from, to) {\n\n}\n\nfunction cook(chicken,pork,beef) {\n\n}\n\n", before_exec_code.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/,'__XMP_MARKER__')


  end

  def test_prepare_code
    xmp = XMPCompleteFilter.new(:use_spec => false)
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_complete.js")).join
    
    newcode = []
    code.to_a.each_with_index{|line, i|
      if i+1 == 10
        newcode.push(xmp.prepare_line(line.chomp, nil))
      else
        newcode.push(line)
      end
    }

    final_code = xmp.prepare_code(newcode.join)
    assert_equal "var test_obj = {  p: defun ,  place: cook,  a: [1,2,3] ,  d: {one:1,  two: '2'  },  b:false};(function(jct_target) {  var members = [];  var jct_k;  for (jct_k in jct_target) {    if (jct_target[jct_k].constructor === Array) {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '[]' + '|' + jct_k);    } else if (jct_target[jct_k].toString() === '[object Object]') {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '{}' + '|' + jct_k);    } else if (typeof jct_target[jct_k] === 'function') {      var function_introspection = jct_target[jct_k].toString();      var sig = jct_k + function_introspection.replace(/\\n*function *[a-zA-Z0-9_]*(\\(.*\\)) *\\{[.\\n]*\\}\\n*/gm, '$1');      members.push('!__XMP_MARKER__![1] ~=> ' + sig + '|' + sig);    } else {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '|' + jct_k);    }  }  print(members.join('\\n'));})(test_obj);function defun(name, len, from, to) {}function cook(chicken,pork,beef) {}", final_code.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/,'__XMP_MARKER__')
  end

  def test_exec
    xmp = XMPCompleteFilter.new(:use_spec => false)
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_complete.js")).join
    
    newcode = []
    code.to_a.each_with_index{|line, i|
      if i+1 == 10
        newcode.push(xmp.prepare_line(line.chomp, nil))
      else
        newcode.push(line)
      end
    }
    stdout, stderr = xmp.execute_complete(newcode.join)
    assert_equal "!![1] ~=> p(name, len, from, to)|p(name, len, from, to)\n!![1] ~=> place(chicken, pork, beef)|place(chicken, pork, beef)\n!![1] ~=> a[]|a\n!![1] ~=> d{}|d\n!![1] ~=> b|b\n", stdout.readlines.join.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/,'')

  end
  
  def test_completion_code
    xmp = XMPCompleteFilter.new(:use_spec => false)
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_complete.js")).join

    result = xmp.completion_code(code,10)
    assert_equal "p(name, len, from, to)|p(name, len, from, to)\\nplace(chicken, pork, beef)|place(chicken, pork, beef)\\na[]|a\\nd{}|d\\nb|b", result
  end
end

