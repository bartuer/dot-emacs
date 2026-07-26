#!/bin/bash
pushd /
tar czf /opt/arm64.emacs30.1_24.04.tar.gz --exclude="root/etc/el/.git" -T /opt/arm64.tar.list
popd
