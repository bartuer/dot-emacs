/*
  Date implement has serious bug
 */

var t =  new Date();
t;                               //#=> Fri Oct 21 2011 09:46:51 GMT+0800 (CST)
t.getDate();                     //#=> 21
t.getTime();                     //#=> 1319161611839
t.getMonth();                    //#=> 9
t.getYear();                     //#=> 111

var f = new Date(2011, 10, 1);
f.getYear();                    //#=> 111
f.getMonth();                   //#=> 10
f.getDate();                    //#=> 1



