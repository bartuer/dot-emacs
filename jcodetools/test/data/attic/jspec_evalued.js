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
          expect(i).to(be, 20.3);
        });
     });

    describe
    ('another boolean',
     function () {
       it
       ('should success',
        function () {
          expect(false).to(be_false);
        });
     });

    describe
    ('another number',
     function () {
       it
       ('should success',
        function () {
          expect(5).to(be, 5);
        });
     });

    describe
    ('function',
     function () {
       it
       ('should success',
        function () {
          f = function () {};
          expect(f).to(be_type, 'function');
        });
     });

     describe
    ('null',
     function () {
       it
       ('should success',
        function () {
          var a_null = null;
            expect(a_null).to(be_type, 'object');
            expect(a_null).to(be_null);
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
          expect(v).to(be, '3');
        });
     });

    describe
    ('object',
     function () {
       it
       ('should success',
        function () {
          var obj = {one:1,two:2};
            expect(obj).to(be_type, 'object');
            expect(obj).to(eql, { one:1, two:2 });
        });
     });

    describe
    ('undefined',
     function () {
       it
       ('should success',
        function () {
          expect(function(){akdjs}).to(throw_error, 'ReferenceError: "akdjs" is not defined.');
        });
     });


  });
