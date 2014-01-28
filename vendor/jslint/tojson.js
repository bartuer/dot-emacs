var sys = require('sys');
var fs = require('fs');

function jstojson(a) {
    var input = fs.readFileSync(a, 'utf-8');
    if (!input) {
        sys.print("tojson: Couldn't open file '");
        process.exit(1);
    }
    var json_statement = eval("object_hold_string = " + input);
    sys.print(JSON.stringify(json_statement));

};

jstojson(process.argv[2]);