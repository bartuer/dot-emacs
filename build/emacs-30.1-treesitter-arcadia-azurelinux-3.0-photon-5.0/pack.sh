#!/bin/sh
set -eu

# Build image and run tarball packaging.
# Output tarball will be created in the current folder via bind mount.
# --entrypoint overrides the base image service startup.

IMAGE=mcr.microsoft.com/officepy/codeexecutionjupyterext1:emacs30.1.arcadia

# DOTEMACS_REV busts the `git clone bartuer/dot-emacs` layer every build
# so we always ship HEAD (picks up changes to bartuer-vterm.el, .emacs.el,
# etc.).  Everything above that layer — libvterm, tree-sitter, emacs —
# is still cached by contents, so this is cheap.
DOTEMACS_REV=$(date +%s)
docker build --platform linux/amd64 \
             --build-arg "DOTEMACS_REV=${DOTEMACS_REV}" \
             -t "$IMAGE" .
docker run --rm --platform linux/amd64 --entrypoint sh -w / -v "${PWD}/:/opt" "$IMAGE" /opt/tar.sh
