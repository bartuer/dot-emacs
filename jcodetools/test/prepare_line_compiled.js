v = 2 + 3;
(function (context_obj){
   var uniqid = v;
   var value_line = "!UNIQID![1] => " + (typeof uniqid) + " " + uniqid.toString() + "\n";
   var bind_lines = [];
   return (function() {
             var pn_uniqid;
             try {
               for (pn_uniqid in context_obj) {
                 if ( context_obj.hasOwnProperty(pn_uniqid) &&
                      typeof pn_uniqid !== 'function' ) {
                   bind_lines.push(pn_uniqid);
                 }
               }
               for (pn_uniqid in context_obj) {
                 if (context_obj.hasOwnProperty(pn_uniqid) &&
                     uniqid === context_obj[pn_uniqid] &&
                     pn_uniqid !== "uniqid") {
                   return value_line + bind_lines.join("\n") + "\n" + "!UNIQID![1] ==> " + pn_uniqid;
                 }
               }
               return value_line + bind_lines.join("\n");
             } finally {}
           })();
               })(this);