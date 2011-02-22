(function(a) {
    var input = read(a[0]);
    if (!input) {
        print("tojson: Couldn't open file '");
        quit(1);
    }
    var json_statement = eval("object_hold_string = " + input);
    print(JSON.stringify(json_statement));

} (arguments));