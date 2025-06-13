caffeinate docker buildx build  --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.devbox:22.04
# caffeinate docker buildx build --no-cache --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.devbox:22.04

