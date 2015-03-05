file /Users/bartuer/local/src/v8/d8_g
cd /Users/bartuer/local/src/v8
set args --trace-codegen --print-ir --print-ast --print-code --print-builtin-code  -- /Users/bartuer/local/src/v8/tools/splaytree.js
rbreak v8::internal::FullCodeGenerator::*

