define j
  source ~/etc/el/gdb/sphinx-search.gdb
end

document j
  "restart the debug session"
end


cd ~/local/src/topsphinx/vendor/sphinx-han/src
file search
set args "ab"
b LoadTokenizerSettings
command 2
  watch tSettings.m_sCharDict
end