/*
 * check out this http://www.datejs.com/
 */
var date = {};

/**
 * Create date
 * @param none
 * @return number
 *
 */
date.new = function () {

};
var f = new Date(2011, 10, 1);

var t =  new Date();

/**
 * Return date number of Date
 * @param none
 * @return number
 *
 */
date.getDate = function () {

};
t.getDate();                     //#=> 21

/**
 * Return million seconds number
 * @param none
 * @return number
 *
 */
date.getTime = function () {

};
t.getTime();                     //#=> 1319161611839


/*
 * getMonth implement has SERIOUS BUG
 * Return month number
 * @param none
 * @return number
 *
 */
date.getMonth = function () {

};
t.getMonth();                    //#=> 9
                                 //t #=> Fri Oct 21 2011 09:46:51 GMT+0800 (CST)

/*
 * Return year number from 1900
 * @param none
 * @return number
 *
 */
date.getYear = function () {

};
t.getYear();                     //#=> 111





