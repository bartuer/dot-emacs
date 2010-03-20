function jcti(jct_target) {
  var members = [];
  var jct_k;
  for (jct_k in jct_target) {
    var o;
    try {
      o = jct_target[jct_k];
    } catch(e) {
      o = null;
      continue;
    }
    if (o === null) {
      members.push(' ' + jct_k + ':null' + ':' + jct_k);
    } else if (o.constructor === Array) {
      members.push(' ' + jct_k + '[' + o.length + ']' + ':' + jct_k + '[' + (o.length - 1) + ']');
    } else if (typeof o === 'function') {
      var a = o.toString().split('\n');
      var sig = jct_k + a[0].replace(/function *[a-zA-Z0-9_]*(\(.*\)) *\{/g, '$1');
      members.push(' ' + sig + ':' + sig);
    } else if (/\\[object .*\\]/.test(o.toString())) {
      var type = o.toString().match(/\\[object (.*)\\]/)[1];
      members.push(' ' + jct_k + '{ ' + type + ' }' + ':' + jct_k + '{}');
    } else if (typeof o === 'string'){
      members.push(' ' + jct_k + ' str: ' + o +  ':' + jct_k);
    } else if (typeof o === 'number'){
      members.push(' ' + jct_k + ' num: ' +  o +  ':' + jct_k);
    } else if (typeof o === 'boolean'){
      members.push(' ' + jct_k + ' boolean: ' + o +  ':' + jct_k);
    } else {
      members.push(' ' + jct_k + ':' + jct_k);
    }
  }
  return members.join('\n');
}
