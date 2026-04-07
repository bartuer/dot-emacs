#!/bin/sh
set -eu

# Build image and run tarball packaging.
# Output tarball will be created in the current folder via bind mount.
# --entrypoint overrides the base image service startup.

IMAGE=mcr.microsoft.com/officepy/codeexecutionjupyterext1:emacs30.1.arcadia

docker build --platform linux/amd64 -t "$IMAGE" .
docker run --rm --platform linux/amd64 --entrypoint sh -w / -v "${PWD}/:/opt" "$IMAGE" /opt/tar.sh
