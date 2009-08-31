var array = {};

/**
 * The concat method produces a new array containing a shallow copy of
 * this array with the items appended to it. If an item is an array,
 * then each of it's elements is appended individually.
 *
 * @param item
 * @return this array
 * @see push
 */
array.concat = function (item) {

};

var a = ['a', 'b', 'c'];
var b = ['x', 'y', 'z'];
a.concat(b, true);                     //#=> ['a', 'b', 'c', 'x', 'y', 'z', true]

/**
 * The join method makes a string from an array.  It does this by
 * making a string of each of the array's elements, and then
 * concatenating them all together with a separator between them.
 *
 * If you are assembling a string from a large number of pieces, it is
 * usually faster to put the pieces into an array and join them than
 * it is to concatenate the pieces with the + operator.
 *
 * @param separator   The default spearator is ','.  To join without
 * separation, use an empty  string as the separator.
 * @return a string
 */
array.join = function (separator) {

};

a = ['inter', 'nation', 'al', 'ize'];
a.join();                       //#=> 'inter,nation,al,ize'
a.join("");                     //#=> 'internationalize'

/**
 * The pop and push methods make an array work like a stack.  The pop
 * method removes and return the last element in this array.
 *
 * @return If the array is empty, it returns undefined.
 */
array.pop = function () {

};

a = ['1', '2', '3'];
c = a.pop();                    //#=> '3'
a;                              //#=> ['1', '2']
a.pop();
a.pop();
c = a.pop();                    //#=> undefined

/**
 * The push method appends items to the end of an array.  Unlike the
 * concat method, ite modifies the array and appends array items
 * whole.
 *
 * @param item
 * @return new length of the array
 */
array.push = function (item) {

};

a = ['x', 'y', 'z'];
b = ['a', 'b', 'c'];
a.push(b, true);                //#=> 5
a;                              //#=> ['x', 'y', 'z', ['a', 'b', 'c'], true]

/**
 * The reverse method modifies the array by reversing the order of the
 * elements.
 *
 * @return this array
 */
array.reverse = function () {

};

a = ['x', 'y', 'z'];
a.reverse();                    //#=> ['z', 'y', 'x']

/**
 * The shift method removes the first element from an array and return
 * it.
 *
 * shift is much slower than pop, don't know reverse first and pop
 * would be faster?
 *
 * @return the element, If the array is empty, it returns undefined.
 */
array.shift = function () {

};

a = ['x', 'y', 'z'];
a.shift();                      //#=> 'x'
a;                              //#=> ['y', 'z']

/**
 * The slice method make a shalow copy of a portion of an array.  The
 * first element copied will be array[start].  It will stop before
 * copying array[end].
 *
 * @param start If it greater than or eauql to array.length, teh
 * result will be a new empty array
 * @param end The end parameter is optional, and the default is
 * array.length.
 * If either parameter is negative, array.length will add to them to
 * make them nonnegative.
 * @return a new array
 * @see splice
 */
array.slice = function (start, end) {

};

a = ['x', 'y', 'z'];
a.slice(0, 1);                  //#=> ['x']
a.slice(1);                     //#=> ['y', 'z']
a;                              //#=> ['x', 'y', 'z']
a.slice(1, 2);                  //#=> ['y']
a.slice(-2, -1);                //#=> ['y']
a.slice(3);                     //#=> []
a.slice(-1);                    //#=> ['z']
a.slice(-1, -2);                //#=> []
a;                              //#=> ['x', 'y', 'z']

/**
 * The sort method sort the contents of an array in place.  It sorts
 * arrays of numbers INCORRECTLY.
 *
 * @param comaparefn
 * @return modified array
 * @see string.localeCompare
 */
array.sort = function (comaparefn) {

};

/* wrong sort:
 * JavaScript's default comparison function assumes that the elements
 * to be sorted are strings.  It isn't clever enough to test the type
 * of the elements before comaring them, so it converts the numbers to
 * strings as it compares them, ensuring a shockingly incorrect result.
 *
 * Fortunately, you may replace the comparison function with your own.
 * Your comparison function should take two parameters and return 0 if
 * the two parameters are equal, a negative number if the first
 * parameter should come first, and a positive number if the second
 * parameter should come first.
 */

var n = [4, 8, 15, 16, 23, 42];
n.sort();                       //#=> [15, 16, 23, 4, 42, 8]
n;                              //#=> [15, 16, 23, 4, 42, 8]
n.sort(function (a, b) {
         return a - b;
       });
n;                              //#=> [4, 8, 15, 16, 23, 42]

var m = ['aa', 'bb', 'a', 4, 8, 15, 16, 23, 42];
m.sort(function (a, b) {
         if (a === b) {
           return 0;
         }
         if (typeof a === typeof b) {
           return a < b ? -1 : 1;
         }
         return typeof  a < typeof b ? -1 : 1;
       });
m;                              //#=> [4, 8, 15, 16, 23, 42, 'a', 'aa', 'bb']

/*
 * With a smarter comprison function, we can sort an array of objects.
 * To make things easier for the general case, we will write a
 * function that will make comparison functions.
 */

// Function by takes a member name string and returns a comparison
// function that can be used to sort an array of objects that contain
// that member.

var by = function (name) {
  return function (o, p) {
    var a, b;
    if (typeof o === 'object' && typeof p === 'object' && o && p) {
      a = o[name];
      b = p[name];
      if (a === b) {
        return 0;
      }
      if (typeof a === typeof b) {
        return a < b ? -1 : 1 ;
      }
      return typeof a < typeof b ? -1 : 1;
    } else {
      throw {
        name: 'Error' ,
        message: 'Expected an object when sorting by ' + name
      };
    }
  };
};

var s = [
  { first: 'Joe' , last: 'Besser'},
  { first: 'Moe' , last: 'Howard'},
  { first: 'Joe' , last: 'DeRita'},
  { first: 'Shemp' , last: 'Howard'},
  { first: 'Larry' , last: 'Fine'},
  { first: 'Curly' , last: 'Howard'}
];

s.sort(by('first'));
s;                              //#=> [{ first:'Curly', last:'Howard' }, { first:'Joe', last:'DeRita' }, { first:'Joe', last:'Besser' }, { first:'Larry', last:'Fine' }, { first:'Moe', last:'Howard' }, { first:'Shemp', last:'Howard' }]
s.sort(by('first')).sort(by('last'));
s;                              //#=> [{ first:'Joe', last:'Besser' }, { first:'Joe', last:'DeRita' }, { first:'Larry', last:'Fine' }, { first:'Shemp', last:'Howard' }, { first:'Moe', last:'Howard' }, { first:'Curly', last:'Howard' }]

/*
 * The above sort method is not stable, if you want to sort on
 * multiple keys, you again need to do more work.  We can modify by to
 * take a second parameter, another compare method that will be called
 * to break ties when the major key produces a match.
 *
 */

// Function by takes a member name string and an optional minor
// comparison function and returns a comparison function that can be
// used to sort an array of objects that contain that member.  The
// minor comparison function is used to break ties when the o[name]
// and p[name] are equal.

var by2 = function (name, minor) {
  return function (o, p) {
    var a, b;
    if (typeof o === 'object' && typeof p === 'object' && o && p) {
      a = o[name];
      b = p[name];
      if (a === b) {
        return typeof minor === 'function' ? minor(o, p) : 0;
      }
      if (typeof a === typeof b) {
        return a < b ? -1 : 1 ;
      }
      return typeof a < typeof b ? -1 : 1;
    } else {
      throw {
        name: 'Error' ,
        message: 'Expected an object when sorting by ' + name
      };
    }
  };
};

s.sort(by2('last', by2('first')));
s;                              //#=> [{ first:'Joe', last:'Besser' }, { first:'Joe', last:'DeRita' }, { first:'Larry', last:'Fine' }, { first:'Curly', last:'Howard' }, { first:'Moe', last:'Howard' }, { first:'Shemp', last:'Howard' }]
s.sort(by2('first', by2('last')));
s;                              //#=> [{ first:'Curly', last:'Howard' }, { first:'Joe', last:'Besser' }, { first:'Joe', last:'DeRita' }, { first:'Larry', last:'Fine' }, { first:'Moe', last:'Howard' }, { first:'Shemp', last:'Howard' }]


/**
 * The splice method remove elements from an array, replacing them
 * with items.  The most popular use of splice is to delete elements
 * from an array.  Do not confuse splice with slice.
 *
 * @param start postion whitin the array
 * @param deleteCount number to be deleted start from the start parameter
 * @param item optional, these will be inserted at the position
 * @return a array containing the deleted elements
 * @see slice
 */
array.splice = function (start, deleteCount, item) {

};

a = ['a', 'b', 'c'];
var r = a.splice(1, 1, 'ache', 'bug');
r;                              //#=> ['b']
a;                              //#=> ['a', 'ache', 'bug', 'c']

/**
 * The unshift method is like the push method except that it shoves
 * the items onto the front of this arrary insteaf of at the end.
 *
 * @param item
 * @return the array's new length.
 */
array.unshift = function (item) {

};

a = ['a', 'b', 'c'];
r = a.unshift('?', '@');
a;                              //#=> ['?', '@', 'a', 'b', 'c']
r;                              //#=> 5

