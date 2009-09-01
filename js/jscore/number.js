var number = {};

/**
 * The toExponential method convert this number to a string in the
 * exponential form.  The optional fractionDigits parameter controls
 * the number of decimal places.
 *
 * @param fractionDigits should be between 0 and 20.
 * @return string
 */
number.toExponential = function (fractionDigits) {

};

Math.PI.toExponential(0);       //#=> '3e+0'
Math.PI.toExponential(2);       //#=> '3.14e+0'
Math.PI.toExponential(7);       //#=> '3.1415927e+0'
Math.PI.toExponential(16);      //#=> '3.1415926535897931e+0'
Math.PI.toExponential();        //#=> '3.141592653589793e+0'

/**
 * The toFixed method convert this number to a string in the decimal
 * form.  The optional fractionDigits parameter controls the number of
 * decimal places.
 *
 * @param fractionDigits  should be between 0 and 20, default is 0
 * @return string
 */
number.toFixed = function (fractionDigits) {

};

Math.PI.toFixed(0);       //#=> '3'
Math.PI.toFixed(2);       //#=> '3.14'
Math.PI.toFixed(7);       //#=> '3.1415927'
Math.PI.toFixed(16);      //#=> '3.1415926535897931'
Math.PI.toFixed();        //#=> '3'

/**
 * The toPrecision method convert this number to a string in the decimal
 * form.  The optional precision parameter controls the number of
 * digits of precision.
 *
 * @param precision  should be between 1 and 21.
 * @return string
 */
number.toPrecision = function (precision) {

};

Math.PI.toPrecision(2);         //#=> '3.1'
Math.PI.toPrecision(7);         //#=> '3.141593'
Math.PI.toPrecision(16);        //#=> '3.141592653589793'
Math.PI.toPrecision();          //#=> '3.141592653589793'

/**
 * The toString method convert this number to a string.  The optional
 * radix parameter controls radix, or base.
 *
 * The most common case, number.toString() can be written more simply
 * as String(number)
 *
 * @param radix should be between 2 and 36
 * @return string
 */
number.toString = function (radix) {

};

String(2);                      //#=> '2'
Math.PI.toString(8);            //#=> '3.1103755242102643'
Math.PI.toString(2);            //#=> '11.001001000011111101101010100010001000010110100011'
Math.PI.toString(16);           //#=> '3.243f6a8885a3'

/**
 * The isNaN method, but a string like number and boolean are
 * considered NOT NaN.  Indeed it is a Global function, not a Number
 * function.
 *
 * @return boolean
 * @see NEGATIVE_INFINITY, POSTIVE_INFINITY, Infinity, MAX_VALUE
 */
number.isNaN = function () {

};

isNaN(0/0);                     //#=> true
isNaN('hi');                    //#=> true
isNaN(undefined);               //#=> true
isNaN("3");                     //#=> false
isNaN(true);                    //#=> false

/**
 * The isFinite method easy to confuse people, for it means not
 * infinite.  Indeed it is a Global function, not a Number
 * function.
 *
 * @return boolean
 */
number.isFinite = function () {

};

isFinite(Infinity);                 //#=> false
isFinite(Number.NEGATIVE_INFINITY); //#=> false
isFinite(Number.POSTIVE_INFINITY);  //#=> false
isFinite(2);                        //#=> true
Infinity;                           //#=> Infinity
Number.NEGATIVE_INFINITY;           //#=> -Infinity
Number.POSTIVE_INFINITY;            //#=> undefined
Number.MAX_VALUE;                   //#=> 1.7976931348623157e+308

/**
 * The parseInt method parse a string to integrate, if the optional
 * parameter radix is less than 2 or greater than 36, NaN will
 * returned.  If only has str parameter, the radix is decide on the
 * format of the string.
 *
 * @param str string
 * @param radix optinal
 * @return decimal integrate
 * @see parseFloat
 */
number.parseInt = function (str, radix) {

};

parseInt("22", 36);             //#=> 74
parseInt("22", 37);             //#=> NaN
parseInt("10010110", 2);        //#=> 150
parseInt("0xabc");              //#=> 2748
parseInt("010");                //#=> 8
parseInt("09");                 //#=> NaN
parseInt("0xA88");              //#=> 2696

/**
 * The parseFloat method parse a string to Number, it parses and
 * returns the first number that occurs in the string, then, parsing
 * stop and the value is returned. Do not use it parse a non decimal
 * integrate.
 *
 * @param str
 * @return Number
 * @see parseInt
 */
number.parseFloat = function (str) {

};

parseFloat("12.34yu78");                //#=> 12.34
parseFloat("1.2e+23");                  //#=> 1.2e+23
parseFloat("-20932093802938.30133820"); //#=> -20932093802938.3
parseFloat("a88");                      //#=> NaN
parseFloat("0xA88");                    //#=> 0
