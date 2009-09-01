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
    before_exec_code = newcode.join.gsub(/__JCT_FUNC_PARAMETERS_RE__/,  'function *[a-zA-Z0-9_]*(\(.*\)) *\{')
    before_exec_code.gsub!(/__JCT_NEWLINE__/, '\n')
    assert_equal "var test_obj = {\n  a: [1,2,3] ,\n  d: {one:1,\n  two: '2'\n  },\n  b:false,\n  p: defun,\n  place: cook\n};\n(function(jct_target) {  var members = [];  var jct_k;  for (jct_k in jct_target) {    var o = jct_target[jct_k];    if (o === null) {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ':null' + '|' + jct_k);    } else if (o.constructor === Array) {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '[' + o.length + ']' + '|' + jct_k + '[' + (o.length - 1) + ']');    } else if (o.toString() === '[object Object]') {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '{ }' + '|' + jct_k + '{}');    } else if (typeof o === 'function') {      var a = o.toString().split('\\n');      var sig = jct_k + a[1].replace(/function *[a-zA-Z0-9_]*(\\(.*\\)) *\\{/g, '$1');      members.push('!__XMP_MARKER__![1] ~=> ' + sig + '|' + sig);    } else if (typeof o === 'string'){      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ' str: ' + o +  '|' + jct_k);    } else if (typeof o === 'number'){      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ' num: ' +  o +  '|' + jct_k);    } else if (typeof o === 'boolean'){      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ' boolean: ' + o +  '|' + jct_k);    } else {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '|' + jct_k);    }  }  print(members.join('\\n'));})(test_obj);function defun(name, len, from, to) {\n\n}\n\n\nfunction cook(chicken,pork,beef) {\n\n}\n\n", before_exec_code.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/,'__XMP_MARKER__')



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
    assert_equal "var test_obj = {  a: [1,2,3] ,  d: {one:1,  two: '2'  },  b:false,  p: defun,  place: cook};(function(jct_target) {  var members = [];  var jct_k;  for (jct_k in jct_target) {    var o = jct_target[jct_k];    if (o === null) {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ':null' + '|' + jct_k);    } else if (o.constructor === Array) {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '[' + o.length + ']' + '|' + jct_k + '[' + (o.length - 1) + ']');    } else if (o.toString() === '[object Object]') {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '{ }' + '|' + jct_k + '{}');    } else if (typeof o === 'function') {      var a = o.toString().split('\\n');      var sig = jct_k + a[1].replace(/function *[a-zA-Z0-9_]*(\\(.*\\)) *\\{/g, '$1');      members.push('!__XMP_MARKER__![1] ~=> ' + sig + '|' + sig);    } else if (typeof o === 'string'){      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ' str: ' + o +  '|' + jct_k);    } else if (typeof o === 'number'){      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ' num: ' +  o +  '|' + jct_k);    } else if (typeof o === 'boolean'){      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + ' boolean: ' + o +  '|' + jct_k);    } else {      members.push('!__XMP_MARKER__![1] ~=> ' + jct_k + '|' + jct_k);    }  }  print(members.join('\\n'));})(test_obj);function defun(name, len, from, to) {}function cook(chicken,pork,beef) {}", final_code.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/,'__XMP_MARKER__')

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
    assert_equal "!![1] ~=> a[3]|a[2]\n!![1] ~=> d{ }|d{}\n!![1] ~=> b boolean: false|b\n!![1] ~=> p(name, len, from, to)|p(name, len, from, to)\n!![1] ~=> place(chicken, pork, beef)|place(chicken, pork, beef)\n", stdout.readlines.join.gsub(/XMP[0-9]*_[0-9]*_[0-9]*/,'')

  end
  
  def test_completion_code
    xmp = XMPCompleteFilter.new(:use_spec => false)
    code = File.readlines(File.join(File.dirname(__FILE__), "data/attic/jspec_complete.js")).join

    result = xmp.completion_code(code,10)
    assert_equal "a[3]|a[2]__JCT_NEWLINE__d{ }|d{}__JCT_NEWLINE__b boolean: false|b__JCT_NEWLINE__p(name, len, from, to)|p(name, len, from, to)__JCT_NEWLINE__place(chicken, pork, beef)|place(chicken, pork, beef)", result
  end
end

