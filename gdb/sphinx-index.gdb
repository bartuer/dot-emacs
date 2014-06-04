define j
  source ~/etc/el/gdb/sphinx-index.gdb
end

document j
  "restart the debug session"
end


cd ~/local/src/topsphinx/vendor/sphinx-han/src
file ~/local/src/topsphinx/vendor/sphinx-han/src/indexer
set args test1
b CSphTokenizer_UTF8Seg::SetCharDict
b SaveTokenizerSettings
b CSphTokenizerSettings