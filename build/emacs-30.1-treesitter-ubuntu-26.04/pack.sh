#!/bin/bash
set -euo pipefail

docker run --rm --platform linux/amd64 -w / \
  -v "${PWD}:/opt" \
  caapi/amd64.emacs30.1:26.04 \
  /opt/tar.sh