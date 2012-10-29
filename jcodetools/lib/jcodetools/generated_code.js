
function defun(name, len, from, to) {

}

var test_obj = {
             name: "bartuer" ,
             age: 22,
             obj:false,
             a_array:[1, 2, 3],
             a_function: defun,
             dict:{
               one: 1,
               two: "2",
               three: 3,
               four:null,
               five:undefined,
               six:{
                 1: 'one',
                 2: 'two',
                 3: ['a', 1, 'b']
               }
               }
           };


(function test(context_obj){
  var uniqid;
  var value_line = '';
  var exception_line = '';
  var bind_lines = [];
  var symbol_line = '';
  var introspect = function(jct_target) {
    if (jct_target === null) {
      return 'null';
    } else if (typeof jct_target === 'undefined') {
      return 'undefined';
    } else if (typeof jct_target === 'function') {
      return jct_target.toString().replace(/\{[.\n]*\}/gm, '').replace(/\n/gm,'');
    } else if (typeof jct_target === 'string') {
      return '\'' + jct_target + '\'';
    } else if (jct_target.constructor === Array ||
               jct_target.toString() === '[object Object]') {
      var members = [];
      var jct_k;
      for (jct_k in jct_target) {
        if ( jct_target.hasOwnProperty(jct_k)) {
          if (jct_target.constructor === Array) {
            members.push(introspect(jct_target[jct_k]));
          } else {
            members.push(jct_k + ':' + introspect(jct_target[jct_k]));
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
       uniqid = test_obj;
       value_line = '[1] => ' + (typeof uniqid) + ' ' + introspect(uniqid) + '__JCTNEWLINE__';
       for (pn_uniqid in context_obj) {
         if (context_obj.hasOwnProperty(pn_uniqid) &&
             typeof pn_uniqid !== 'function') {
           bind_lines.push(pn_uniqid);
         }
       }
       for (pn_uniqid in context_obj) {
         if (context_obj.hasOwnProperty(pn_uniqid) &&
             uniqid === context_obj[pn_uniqid] &&
             pn_uniqid !== 'test_obj') {
           symbol_line = '__JCTNEWLINE__' + '[1] ==> ' + pn_uniqid;
         }
       }
     } catch(e) {
       exception_line = '[1] ~> ' + e.toString() + '__JCTNEWLINE__';
       throw(e);
     } finally {
       print(exception_line + value_line + bind_lines.join('__JCTNEWLINE__') +  symbol_line);
     }
   })();
 })(this);




