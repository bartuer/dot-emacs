#!/bin/bash
set -euo pipefail

cd /
tar czf /opt/amd64.emacs30.1_26.04.tar.gz \
  --exclude="root/etc/el/.git" \
  -T /opt/amd64.tar.list