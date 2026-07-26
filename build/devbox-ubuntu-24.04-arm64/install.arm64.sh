tar zxf arm64.emacs30.1_24.04.tar.gz -C /
tar zxf arm64.dev.base.24.04.tar.gz -C /
# Optional per-language dev packs (uncomment those you built):
# tar zxf arm64.dev.cc.24.04.tar.gz -C /
# tar zxf arm64.dev.py.24.04.tar.gz -C /
# tar zxf arm64.dev.rs.24.04.tar.gz -C /
# tar zxf arm64.dev.js.24.04.tar.gz -C /
# tar zxf arm64.dev.cs.24.04.tar.gz -C /
ldconfig
source ~/.bashrc
