#!/bin/sh
# Copy pre-built tree-sitter artifacts from the extracted tarball staging area.
# Run after: tar zxf amd64.arcadia.emacs30.1_azl3.0.tar.gz -C /

# tsc-dyn.so (elisp-tree-sitter Rust binding)
cp ~/etc/el/build/emacs-30.1-treesitter-arcadia-azurelinux-3.0-photon-5.0/amd64/vendor/tsc/tsc-dyn.so ~/etc/el/vendor/tsc

# tree-sitter grammar .so files (compiled by treesit-compile.el during docker build)
# These are already at ~/.emacs.d/tree-sitter/ after tarball extraction.
# Copy them into the dot-emacs repo tree for portability.
mkdir -p ~/etc/el/.emacs.d/tree-sitter
cp ~/.emacs.d/tree-sitter/libtree-sitter-*.so ~/etc/el/.emacs.d/tree-sitter/ 2>/dev/null || true
