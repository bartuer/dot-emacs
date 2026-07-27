#!/bin/bash
# Native build of the arm64 dev.base image — for when the HOST arch already
# matches the TARGET arch (arm64), so NO cross-emulation (qemu/binfmt) is needed.
#
# The folder name encodes the target: devbox-ubuntu-24.04-arm64 → target arm64.
# On a native aarch64 host, `docker build` produces genuine arm64 binaries
# directly and fast; `buildx --platform linux/arm64` + qemu is ONLY needed when
# building this target from a non-arm64 host (e.g. x86_64) — use build.macos.sh
# for that path.
#
# Usage (native aarch64 host, direct internet):
#   ./build.base.native.sh          # build image
#   ./pack.base.arm64.sh            # extract arm64.dev.base.24.04.tar.gz
set -eu

TARGET_ARCH=arm64          # derived from folder name (…-arm64)
IMG=caapi/arm64.devbox.base:24.04

# Map uname -m → docker arch token for the host==target check.
case "$(uname -m)" in
  aarch64|arm64) HOST_ARCH=arm64 ;;
  x86_64|amd64)  HOST_ARCH=amd64 ;;
  *)             HOST_ARCH=$(uname -m) ;;
esac

if [ "$HOST_ARCH" != "$TARGET_ARCH" ]; then
  echo "ERROR: host arch ($HOST_ARCH) != target ($TARGET_ARCH)." >&2
  echo "       Native build needs host==target. To CROSS-build $TARGET_ARCH" >&2
  echo "       from $HOST_ARCH, use build.macos.sh (buildx + qemu) instead." >&2
  exit 1
fi

echo "Host arch $HOST_ARCH == target $TARGET_ARCH → native build (no qemu)."
# Plain `docker build` (no --platform, no buildx, no proxy) on a native host.
docker build -f Dockerfile.base . -t "$IMG"
echo "Built $IMG. Next: ./pack.base.arm64.sh"
