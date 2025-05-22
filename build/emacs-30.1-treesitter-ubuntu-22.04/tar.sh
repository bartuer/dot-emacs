#!/bin/bash
pushd /
tar czf /opt/Downloads/arm64.emacs30.1_22.04.tar.gz --exclude="root/etc/el/.git" -T /root/etc/el/build/emacs-30.1-treesitter-ubuntu-22.04/arm64.tar.list
popd