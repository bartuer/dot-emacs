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
