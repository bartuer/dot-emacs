#!/bin/sh
set -eu

IMAGE=mcr.microsoft.com/officepy/codeexecutionjupyterext1:dev.base.arcadia

docker build --platform linux/amd64 -t "$IMAGE" .
docker run --rm --platform linux/amd64 --entrypoint sh -w / -v "${PWD}/:/opt" "$IMAGE" /opt/tar.sh
