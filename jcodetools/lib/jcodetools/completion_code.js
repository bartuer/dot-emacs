
function defun(name, len, from, to) {

}

function cook(chicken,pork,beef) {

}

var test_obj = {
  p: defun ,
  place: cook,
  a: [1,2,3] ,
  d: {one:1,
  two: '2'
  },
  b:false
};

(function test(jct_target) {
  var members = [];
  var jct_k;
  for (jct_k in jct_target) {
    var o = jct_target[jct_k];
    if (o === null) {
      members.push('' + jct_k + ':null' + '|' + jct_k);
    } else if (o.constructor === Array) {
      members.push('' + jct_k + '[' + o.length + ']' + '|' + jct_k + '[' + (o.length - 1) + ']');
    } else if (typeof o === 'function') {
      var a = o.toString().split('__JCT_NEWLINE__');
      var sig = jct_k + a[0].replace(/__JCT_FUNC_PARAMETERS_RE__/g, '$1');
      members.push('' + sig + '|' + sig);
    } else if (/\\[object .*\\]/.test(o.toString())) {
      var type = o.toString().match(/\\[object (.*)\\]/)[1];
      members.push('' + jct_k + '{ ' + type + ' }' + '|' + jct_k + '{}');
    } else if (typeof o === 'string'){
      members.push('' + jct_k + ' str: ' + o +  '|' + jct_k);
    } else if (typeof o === 'number'){
      members.push('' + jct_k + ' num: ' +  o +  '|' + jct_k);
    } else if (typeof o === 'boolean'){
      members.push('' + jct_k + ' boolean: ' + o +  '|' + jct_k);
    } else {
      members.push('' + jct_k + '|' + jct_k);
    }
  }
  repl.print(members.join('__JCT_NEWLINE__'));
})(test_obj);

function defun(name,  from, to) {
    this.headers = {};
    this.responseHeaders = {};
}


function cook(chicken,pork,beef) {

}

var test_obj = {
  a: [1,2,3,4,5,6,7] ,
  d: {one:1,
  two: '2',
  three: true
  },
  bbbbb:false,
  p: defun,
  place: cook
};

test_obj.dom = function(name, num) {

};


for (jjjc in test_obj) {
  jjjc                          //#=>
}

if (typeof Object.create !== 'function') {
  Object.create = function (o) {
    var F = function () {};
    F.prototype = o;
    return new F();
  };
}

