file ~/local/src/v8/d8_g
cd ~/local/src/v8
set args --expose_debug_as v8debugger ~/local/src/baza/public/javascripts/debug.js
b d8-debug.cc:139
r
