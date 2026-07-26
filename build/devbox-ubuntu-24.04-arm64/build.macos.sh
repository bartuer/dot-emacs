caffeinate docker buildx build  --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.devbox.build:24.04
# Direct-internet Linux host (no corp proxy, no caffeinate): drop both, e.g.
# docker buildx build --progress=plain --platform linux/arm64 . -t caapi/arm64.devbox.build:24.04
#
# BASE-ONLY (recommended for the arm64 deliverable — plan Group 3):
# the full Dockerfile above couples dev.base to the cc/rs/js/py/cs language
# packs via COPY --from, forcing the entire cargo/npm/uv/dotnet chain to build
# under QEMU (slow + fragile). Use Dockerfile.base to build dev.base directly:
#   docker buildx build --progress=plain --platform linux/arm64 \
#     -f Dockerfile.base . -t caapi/arm64.devbox.base:24.04
#   ./pack.base.arm64.sh   # extracts arm64.dev.base.24.04.tar.gz
