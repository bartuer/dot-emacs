
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


(function test(context_obj){
   (function(jct_target) {
      var members = [];
      var jct_k;
      for (jct_k in jct_target) {
        if (jct_target[jct_k].constructor === Array) {
          members.push(jct_k + '[]' + '|' + jct_k);
        } else if (jct_target[jct_k].toString() === '[object Object]') {
          members.push(jct_k + '{}' + '|' + jct_k);
        } else if (typeof jct_target[jct_k] === 'function') {
          var function_introspection = jct_target[jct_k].toString();
          var sig = jct_k + function_introspection.replace(/\n*function *[a-zA-Z0-9_]*(\(.*\)) *\{[.\n]*\}\n*/gm, '$1');
          members.push(sig + '|' + sig);
        } else {
          members.push(jct_k + '|' + jct_k);
        }
      }
      print(members.join("\n"));
  })(test_obj);
 })(this);





load('/Users/bartuer/etc/el/js/env.js');
var nav = window.navigator;
load('/Users/bartuer/local/src/jspec/lib/jspec.js');
function inspector(jct_target) {
  var members = [];
  var jct_k;
  for (jct_k in jct_target.prototype) {
    if (jct_target[jct_k] === null) {
      members.push('NULL ' + jct_k + + '|' + jct_k);
    }
    else if (jct_target[jct_k].constructor === Array) {
      members.push('ARRAY ' + jct_k + '[]' + '|' + jct_k);
    } else if (jct_target[jct_k].toString() === '[object Object]') {
      members.push('OBJ ' + jct_k + '{}' + '|' + jct_k);
    } else if (typeof jct_target[jct_k] === 'function')
      members.push('FUNC ' + jct_k + 'function(){}' + '|' + jct_k);
    else {
      members.push('ELSE ' + jct_k + '|' + jct_k);
    }
  }
  return members;
}

function pinspector(jct_target) {
  var members = [];
  var jct_k;

  if (typeof jct_target) {
    for (jct_k in String.prototype) {
      if (jct_target[jct_k] === null) {
        members.push('NULL ' + jct_k  + '|' + jct_k);
      }
      else if (jct_target[jct_k].constructor === Array) {
        members.push('ARRAY ' + jct_k + '[]' + '|' + jct_k);
      } else if (jct_target[jct_k].toString() === '[object Object]') {
        members.push('OBJ ' + jct_k + '{}' + '|' + jct_k);
      } else if (typeof jct_target[jct_k] === 'function') {
        members.push('FUNC ' + jct_k + 'function(){}' + '|' + jct_k);
      } else {
        members.push('ELSE ' + jct_k + '|' + jct_k);
      }
    }

    return members;
    }
}

i = [2, 4]                      //#=> [2, 4]

inspector(nav)                  //

inspector(i)                    //

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

typeof test_obj.d.one                  //#=> 'number'

String.prototype
typeof String.prototype
String.prototype.length
String.length
typeof String

str = new String();
pinspector(str)                 //#=> []

for (jjjc in test_obj) {
  jjjc                          //#=> 'a', 'd', 'bbbbb', 'p', 'place', 'dom'
}

if (typeof Object.create !== 'function') {
  Object.create = function (o) {
    var F = function () {};
    F.prototype = o;
    return new F();
  };
}

