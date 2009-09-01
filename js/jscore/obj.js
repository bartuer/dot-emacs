var obj = {};

/**
 * The hasOwnProperty method returns true if this contains a
 * property.  The prototype chain is notexamined.  This method is
 * useless if the name is hasOwnProperty.
 *
 * @param name
 * @return boolean
 */
obj.hasOwnProperty = function (name) {

};

var o = {};
o.hasOwnProperty('length');         //#=> false
o.hasOwnProperty('hasOwnProperty'); //#=> false
Object.prototype.hasOwnProperty('hasOwnProperty'); //#=> true

if (typeof Object.create !== 'function') {
  Object.create = function (o) {
    var F = function () {};
    F.prototype = o;
    return new F();
  };
}

o.name = 'proptotype chain';
var b = Object.create(o);
b.hasOwnProperty('name');       //#=> false
b.name;                         //#=> 'proptotype chain'
