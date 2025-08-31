#!/bin/bash
pushd /
tar czf /opt/Downloads/amd64.emacs30.1_24.04.tar.gz --exclude="root/etc/el/.git" -T /root/etc/el/build/emacs-30.1-treesitter-ubuntu-24.04/amd64.tar.list
popd