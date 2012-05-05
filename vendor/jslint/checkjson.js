(function (a) {
  var data = read(a[0]);
  if (!data) {
    print("checkjson: Couldn't open file '");
    return -2;
  }
  try {
    JSON.parse(data);
    print('no problem');
    return 0;
  } catch (e) {
    print('bad json');
    return -1;
  }
}(arguments));
