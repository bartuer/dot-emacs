#!/bin/sh
set -eu

# Create tarball at /opt so it can be bind-mounted out by pack.sh
# Exclude any VCS folder to keep tarball small and stable.
cd /

tar czf /opt/amd64.arcadia.emacs30.1_azl3.0.tar.gz \
  --exclude="root/etc/el/.git" \
  -T /opt/amd64.tar.list
