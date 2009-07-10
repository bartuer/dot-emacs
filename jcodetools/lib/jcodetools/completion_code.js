
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




