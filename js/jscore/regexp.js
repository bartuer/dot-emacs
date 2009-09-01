var regexp = {};

/**
 * The exec method is the most powerful and slowest method that use
 * regular expressions.  If it successfully matches the regexp and the
 * string, it returns an array.  The 0 element of the array will
 * contain the substring that matched the regexp.  The 1 element is
 * the text captured by group 1, the 2 element is the text captured by
 * group 2, and so on.  If the match fails it returns null.
 *
 * If the regexp has a g flag, things are a little more complicated.
 * The searching begins not at the postion 0 of the string, but at
 * position regexp.lastIndex which is initally zero.  If the match is
 * successful, then regexp.lastIndex will be set to the postion of the
 * first character after the match.  An unsuccessful match resets
 * regexp.lastIndex to 0.
 *
 * This allows you to search for several occurrences of a pattern in a
 * string by calling exec in a loop.  There are a couple things to
 * watch out for.  If you exit the loop early, you must rest
 * regexp.lastIndex to 0 yourself before entering the loop again.
 * Also. the ^ factor matches only when regexp.lastIndex is 0.
 *
 * @param string
 * @return array, failed null
 */
regexp.exec = function (string) {

};

/*
 * Break a simple html text into tags and texts.
 * For each tag or text, produce an array containing
 * [0] The full matched tag or text
 * [1] The tag name
 * [2] The /, if there is one
 * [3] The attributes, if any
 * see string.replace for entifyify method
 */

var html = '<html><body bgcolor=linen><p>' + 'This is <b>bold<\/b>!</p><\/body><\/html>';
var tags = /[^<>]+|<(\/?)([A-Za-z]+)([^<>]*)>/g;
var a;
while((a = tags.exec(html))) {
  a;                            //#=> ['<html>', '', 'html', '', 0, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['<body bgcolor=linen>', '', 'body', ' bgcolor=linen', 6, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['<p>', '', 'p', '', 26, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['This is ', undefined, undefined, undefined, 29, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['<b>', '', 'b', '', 37, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['bold', undefined, undefined, undefined, 40, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['</b>', '/', 'b', '', 44, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['!', undefined, undefined, undefined, 48, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['</p>', '/', 'p', '', 49, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['</body>', '/', 'body', '', 53, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>'], ['</html>', '/', 'html', '', 60, '<html><body bgcolor=linen><p>This is <b>bold</b>!</p></body></html>']
};

while((a = tags(html))){
  for (var i = 0; i < a.length; i +=1) {
    '[' + i + ']' + a[i];       //#=> '[0]<html>', '[1]', '[2]html', '[3]', '[0]<body bgcolor=linen>', '[1]', '[2]body', '[3] bgcolor=linen', '[0]<p>', '[1]', '[2]p', '[3]', '[0]This is ', '[1]undefined', '[2]undefined', '[3]undefined', '[0]<b>', '[1]', '[2]b', '[3]', '[0]bold', '[1]undefined', '[2]undefined', '[3]undefined', '[0]</b>', '[1]/', '[2]b', '[3]', '[0]!', '[1]undefined', '[2]undefined', '[3]undefined', '[0]</p>', '[1]/', '[2]p', '[3]', '[0]</body>', '[1]/', '[2]body', '[3]', '[0]</html>', '[1]/', '[2]html', '[3]'
  }
}


/**
 * The test method is the simplest and fastest of the methods that use
 * regular expressions.  If the regexp matches the string, it returns
 * true; otherwise, it returns false.  Do not use the g flag with this
 * method.
 *
 * @param string
 * @return boolean
 */
regexp.test = function (string) {

};

var r = /&.+;/.test('frank &amp; beans'); //#=> true
