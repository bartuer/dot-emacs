#!/usr/bin/env node

fs = require('fs');
fs.readFile(process.argv[2], function (err, data) {
try {
  JSON.parse(data);
  console.log('no problem');
  process.exit(0);
} catch(e) {
  console.log('bad json');
  process.exit(-1);
}
});
