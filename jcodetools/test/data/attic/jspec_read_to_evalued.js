 /*jslint
  */


JSpec.describe(
  'Value',

  function () {
    before_each(
      function () {
      });

    describe
    ('number',
     function () {
       it
       ('should eq two number',
        function () {
          var i = 20.3;
          i                     //#=>
        });
     });

    describe
    ('another boolean',
     function () {
       it
       ('should success',
        function () {
          false                 //#=>
        });
     });

    describe
    ('another number',
     function () {
       it
       ('should success',
        function () {
          5                     //#=>
        });
     });

    describe
    ('function',
     function () {
       it
       ('should success',
        function () {
          f = function () {};
          f                     //#=>
        });
     });

     describe
    ('null',
     function () {
       it
       ('should success',
        function () {
          var a_null = null;
            a_null              //#=>
        });
     });

    describe
    ('string',
     function () {
       it
       ('should success',
        function () {
          var i = 3;
          v = i.toString();
          v                     //#=>
        });
     });

    describe
    ('object',
     function () {
       it
       ('should success',
        function () {
          var obj = {one:1,two:2};
            obj                 //#=>
        });
     });

    describe
    ('undefined',
     function () {
       it
       ('should success',
        function () {
          akdjs                 //#=>
        });
     });


  });
