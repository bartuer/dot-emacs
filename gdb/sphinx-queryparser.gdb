cd ~/local/src/topsphinx/vendor/sphinx-han/src
set args --noinfo --config ~/local/src/bla/test/fixtures/config/development.sphinx.conf --index item_core --ext2 '舒|汽车'
file ~/local/src/topsphinx/vendor/sphinx-han/src/search
b sphParseExtendedQuery
run
set yydebug=1

