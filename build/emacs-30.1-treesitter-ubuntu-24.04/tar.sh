#!/bin/bash
pushd /
tar czf /opt/amd64.emacs30.1_24.04.tar.gz --exclude="root/etc/el/.git" -T /opt/amd64.tar.list
popd