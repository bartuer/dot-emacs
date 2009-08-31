var func  = {};

/**
 * The apply method invokes a function, passing in the object that
 * will be bound to this and an optional array of arguments.  The
 * apply method is used in the apply invocation pattern.
 *
 * @param thisArg
 * @param argArray
 * @return
 */
func.apply = function (thisArg, argArray) {

};

/*
 * show curry usage, you could pack lots of things in a object, then
 * use it to define a function, such values would also be available at
 * runtime.
 */

Function.prototype.bind = function (that) {
                            var method = this;
                            var slice = Array.prototype.slice;
                            var args = slice.apply(arguments, [1]);
                            return function () {
                              return method.apply(that,
                                                  args.concat(slice.apply(arguments, [0])));
                            };
};

var data = {
  value: 4,
  name: 'hook' ,
  age: 78
};

var x = function () {
  return this.value;
}.bind(data);

x();                            //#=> 4
data.value = data.age;
x();                            //#=> 78
data.age = 77;
x();                            //#=> 78
data.value = data.age;
x();                            //#=> 77
data.name = 'Ford';
data.value = data.name;
x();                            //#=> 'Ford'
