cd ~/local/src/topsphinx/vendor/sphinx-han/src
file searchd
set args --config ~/local/src/bla/test/fixtures/config/development.sphinx.conf   --console
b sphParseExtendedQuery
b sphinxquery.cpp:944
run
