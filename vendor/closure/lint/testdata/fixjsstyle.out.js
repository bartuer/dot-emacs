// Copyright 2008 The Closure Linter Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS-IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * @fileoverview Autofix test script.
 *
 * @author robbyw@google.com (Robby Walker)
 * @author robbyw@google.com (Robby Walker)
 * @author robbyw@google.com (Robby Walker)
 */

goog.provide('X');
goog.provide('Y');
goog.provide('Z');
goog.provide('w');

goog.require('dummy.Bb');
goog.require('dummy.Cc');
goog.require('dummy.aa');

var x = new dummy.Bb();
dummy.Cc.someMethod();
dummy.aa.someMethod();


/**
 * @param {?number} badTypeWithExtraSpace |null -> ?.
 * @return {number} returns -> return.
 */
x.y = function(badTypeWithExtraSpace) {
};

spaceBeforeSemicolon = 10;
spaceBeforeParen = 10 + (5 * 2);
arrayNoSpace = [10];
arrayExtraSpace[10] = 10;
spaceBeforeClose = ([10]);
spaceAfterStart = ([10]);
extraSpaceAfterPlus = 10 + 20;
extraSpaceBeforeOperator = x++;
extraSpaceBeforeOperator = x--;
extraSpaceBeforeComma = x(y, z);
missingSpaceBeforeOperator = x + y;
missingSpaceAfterOperator = x + y;
missingBothSpaces = x + y;
equalsSpacing = 10;
equalsSpacing = 10;
equalsSpacing = 10;
equalsSpacing = [10];
reallyReallyReallyReallyReallyReallyReallyReallyReallyReallyReallyLongName = 1000;

'string should be single quotes';

// Regression test for interaction between space fixing and semicolon fixing -
// previously the fix for the missing space caused the function to be seen as
// a non-assigned function and then its semicolon was being stripped.
x = function() {
};


/**
 * @param {string} a <code>Add a period before tag code.</code>
 * @param {Object} b An object with the following properties:
 *     <ul>
 *       <li>'name' - The human readable name of the object.</li>
 *       <li>'id' - The unique id fo the object: missing period.</li>
 *     </ul>
 * @return {boolean} Add a period.
 */
function xyz(a, b) {
}



/**
 * Missing a newline.
 * @constructor
 * @extends {a.b.c}
 */
x.y.z = function() {
};
goog.inherits(x.y.z, a.b.c);



/**
 * Extra blank line.
 * @constructor
 * @extends {a.b.c}
 */
x.y.z = function() {
};
goog.inherits(x.y.z, a.b.c);



/**
 * Perfect!
 * @constructor
 * @extends {a.b.c}
 */
x.y.z = function() {
};
goog.inherits(x.y.z, a.b.c);

// Whitespace at end of comment.
var removeWhiteSpaceAtEndOfLine;


/**
 * Whitespace at EOL (here and the line of code and the one below it).
 * @type {string}
 * @param {string} Description with whitespace at EOL.
 */
x = 10;


/**
 * @type {number}
 */
foo.bar = 3;


/**
 * @enum {boolean}
 */
bar.baz = true;


/**
 * @extends {Object}
 */
bar.foo = x;


/**
 * @type {function(string, boolean) : void}
 */
baz.bar = goog.nullFunction;


/** @inheritDoc */
baz.baz = function() {
};

TR_Node.splitDomTreeAt(splitNode, clone, /** @type {Node} */ (quoteNode));

x = [1, 2, 3];
x = {
  a: 1
};

if (x) {
}

for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}
for (i = 0; i < 10; i++) {
}

var x = 10;
var y = 100;

var indent = 'correct';
indent = 'too far';
if (indent) {
  indent = 'too short';
}
indent = function() {
  return a +
      b;
};


/**
 * This is to test the ability to remove multiple extra lines before a top-level
 * block.
 */
function someFunction() {}


/**
 * This is to test the ability to add multiple extra lines before a top-level
 * block.
 */
function someFunction() {}


/**
 * This is to test punctuation mark injection in comments with HTML tags.
 * @param {string} v A value to be <a><code>ignored.</code></a>
 */
function someFunction(v) {}


// This is a comment.
/**
 * This is to test that blank lines removed before a top level block skips any
 * comments above the block.
 */
function someFunction() {}


// This is a comment.
/**
 * This is to test that blank lines added before a top level block skips any
 * comments above the block.
 */
function someFunction() {}

// Previously, when auto-fixing the below line there would not be a space
// between the . and the */
/** @desc Single line description. */

// File does not end with newline
