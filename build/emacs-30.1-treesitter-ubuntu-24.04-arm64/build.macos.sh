docker buildx build --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.emacs30.1:24.04
# Direct-internet Linux host (no corp proxy): drop the --build-arg above, e.g.
# docker buildx build --progress=plain --platform linux/arm64 . -t caapi/arm64.emacs30.1:24.04
