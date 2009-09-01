var str = {};

/**
 * The charAt method return the char at pos, if pos is less than zero
 * or greater than or equal to string.length, it returns the empty
 * string.  JavaScript does not have a character type, the result of
 * this method is string.
 *
 * @param pos
 * @return char at position pos in string
 */
str.charAt = function (pos) {

};

var name = 'Curly';
var initial = name.charAt(0);   //#=> 'C'

/**
 * The charCodeAt method is same as charAt except that instead of
 * returning a string, it returns an integer representation of the
 * code point value of the charactor at position pos in that string.
 * If pos is less than zero or greater than or equal to string.less,
 * it returns NaN.
 *
 * @param pos
 * @return number
 */
str.charCodeAt = function (pos) {

};

name.charCodeAt(0);             //#=> 67

/**
 * The concat method makes a new string by concatenating other strings
 * together.  It is rarely used because the + operator is more
 * convenient.
 *
 * @param string
 * @return new string
 */
str.concat = function (string) {

};

'Name '.concat(name, ' is a name'); //#=> 'Name Curly is a name'

/**
 * The indexOf method searches for a searchString within a string.  If
 * it is found, it returns the position of the first matched character;
 * otherwise, it returns -1.  The optional position parameter causes
 * the search to begin at some specified position in the string.
 *
 * @param searchString
 * @param position
 * @return number
 */
str.indexOf = function (searchString, position) {

};

var text = 'Mississippi';
text.indexOf('ss');             //#=> 2
text.indexOf('ss', 3);          //#=> 5
text.indexOf('ss', 6);          //#=> -1

/**
 * The lastIndexOf method is like the indexOf, except that is searches
 * from the end of the string instead of the front.
 *
 * @param searchString
 * @param position
 * @return number
 */
str.lastIndexOf = function (searchString, position) {

};

text.lastIndexOf('ss');         //#=> 5
text.lastIndexOf('ss', 3);      //#=> 2
text.lastIndexOf('ss', 6);      //#=> 5

/**
 * The localCompare method compares two strings.  The rules for how
 * the strings are compared are not specified.  If this string is less
 * than that string, the result is negative.  If they are equal, the
 * result is zero.  This is similar to the convention for the
 * array.sort comparison function.
 *
 * @param that
 * @return number, negative, zero, or nonnegative
 */
str.localCompare = function (that) {

};

var m = ['AAA', 'A', 'aa', 'a', 'Aa', 'aaa'];
m.sort(function (a, b) {
         return a.localeCompare(b);
       });

m;                              //#=> ['a', 'A', 'aa', 'Aa', 'aaa', 'AAA']

/**
 * The match method matches a string and a regular expression.  How it
 * does this depends on the g flag.  If there is no g flag, then the
 * result of calling string.matche(regexp) is the same as calling
 * regexp.exec(string).  However, if the regexp has the g flag, then it
 * produces an array of all the matches but excludes the capturing
 * groups.
 *
 * @param regexp
 * @return array or
 */
str.match = function (regexp) {

};

'first1sencond2third3fourth1fifth2sixth3'.match(/([a-z]+[1-3])/);  //#=> ['first1', 'first1', 0, 'first1sencond2third3fourth1fifth2sixth3']
'first1sencond2third3fourth1fifth2sixth3'.match(/([a-z]+[1-3])/g); //#=> ['first1', 'sencond2', 'third3', 'fourth1', 'fifth2', 'sixth3']

/**
 * The replace method does a search and replace operation on this
 * string, producing a new string.  The searchValue argument can be a
 * string or a regular expression object.  If it is a string, only the
 * first occurrence of the searchValue is replaced.  If searchValue is
 * a regexp and if it has the g flag, then it will replace all
 * occurrences.  If it does not have a g flag, then it will replace
 * only the first occurrence.
 *
 * The replaceValue can be a string or a function, if the replaceValue
 * is a string, the character $ has special meaning:
 *
 *    $$           $
 *    $&           the matched text
 *    $number      capture group text
 *    $`           the text preceding the match
 *    $'           the text following the match
 *
 * If the replaceValue is a function, it will be called for each
 * match, and the string returned by the function will be used as the
 * replacement text.  The first parameter passed to the fucntion is
 * the matched text.  The second parameter is the text of capture
 * group 1, the next parameter is the text of capture group 2, and so
 * on.
 *
 * @param searchValue  string or regexp
 * @param replaceValue  string or function
 * @return new string
 */
str.replace = function (searchValue, replaceValue) {

};

// the searchValue is string , so only first occurrence is replace,
// which might be a disappointment.
var result = "mother_in_law".replace('_', '-'); //#=> 'mother-in_law'

var old_area_code = /\((\d{3})\)/g;
var p = '(555)666-1212'.replace(old_area_code, '$1-'); //#=> '555-666-1212'

String.prototype.entityify = (function () {
  var charactor = {
        '<': '&lt;' ,
        '>': '&gt;' ,
        '&': '&amp;' ,
        '\"': '&quote;'
  };

  return function () {
    return this.replace(/[<>&\"]/g, function (c) {
      return charactor[c];
      });
  };
}());
// returned a function call, not the function and wrap it. see module yas
// (link "~/etc/el/vendor/yasnippet/snippets/text-mode/js2-mode/module" 59)


"<&>".entityify();              //#=> '&lt;&amp;&gt;'

/**
 * The search method is like the indexOf method, except that it takes
 * a regexp instead of a string.  It returns the position of the first
 * character of the first match, if there is one, or -1 if the search
 * fails.  The g flag is ignored.  There is no position parameter.
 *
 * @param regexp
 * @return number, failed search return -1
 */
str.search = function (regexp) {

};

text = 'and in it he says "Any damn fool could';
text.search(/[\"\']/);           //#=> 18

/**
 * The slice method makes a new string by copying a portion of another
 * string.  If the start parameter is negative, it add string.length
 * to it.  The end parameter is optional, and its default value is
 * string.length.  If the end parameter is negative, then
 * string.length is added to it. The end parameter is one greater
 * than the position of the last character.  To get n characters
 * starting at position p, use string.slice(p, p + n).
 *
 * @param start
 * @param end
 * @return new string
 * @see substring and array.slice
 */
str.slice = function (start, end) {

};

text.slice(18);                 //#=> '"Any damn fool could'
text.slice(0, 3);               //#=> 'and'
text.slice(-5);                 //#=> 'could'
text.slice(19, 32);             //#=> 'Any damn fool'

/**
 * The split method creates an array of strings by splitting this
 * string into pieces.  The optional limit parameter can limit the
 * number of pieces that will be split.  The separator parameter can
 * be a string or a regexp.
 *
 * @param separator
 * @param limit
 * @return array of strings
 */
str.split = function (separator, limit) {

};

// try on rhino, spidermonkey, squirrelfish and v8, seems Ford's result has problem.
var digit = '0123456789';
var a = digit.split('', 5);     //#=> ['0', '1', '2', '3', '4']

var ip = '192.168.1.0';
ip.split('.');                  //#=> ['192', '168', '1', '0']

'|a|b|c|'.split('|');           //#=> ['', 'a', 'b', 'c', '']

text = 'last, first, middle';
text.split(/\s*,\s*/);          //#=> ['last', 'first', 'middle']
text.split(/\s*(,)\s*/);        //#=> ['last', ',', 'first', ',', 'middle']

/**
 * The substring method is the same as the slice method except that it
 * does not handle the adjustment for negative parameters.  There is
 * no reason to use the substring method.  Use slice instead.
 *
 * @param start
 * @param end
 * @return new string
 */
str.substring = function (start, end) {

};

/**
 * The toLocaleLowerCase method produces a new string that is made by
 * converting this string to lowercase using the rules for the
 * locale.  This is primarily for the benefit of Turkish because in
 * that language 'I' converts to 1, not 'i'.
 *
 * @return string
 */
str.toLocaleLowerCase = function () {

};

/**
 * The toLocaleUpperCase method produces a new string that is made by
 * converting this string to uppercase using the rules for the
 * locale.  This is primarily for the benefit of Turkish because in
 * that languagee 'i' converts to '', not 'I'.
 *
 * @return string
 */
str.toLocaleUpperCase = function () {

};

/**
 * The toLowerCase method produces a new string that is made by
 * converting this string to lowercase.
 *
 * @return string
 */
str.toLowerCase = function () {

};

'ABC'.toLowerCase();            //#=> 'abc'

/**
 * The toUpperCase method produces a new string that is made by
 * converting this string to uppercase.
 *
 * @return string
 */
str.toUpperCase = function () {

};

'abC'.toUpperCase();            //#=> 'ABC'

/**
 * The fromCharCode method produces a string from a series of numbers.
 *
 * @param char
 * @return string
 */
str.fromCharCode = function (integer_for_char) {

};

String.fromCharCode(67, 97, 116); //#=> 'Cat'
