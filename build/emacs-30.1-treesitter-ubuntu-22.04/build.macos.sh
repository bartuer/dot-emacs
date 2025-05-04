docker buildx build --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.emacs30.1:22.04
# docker build . -f Dockerfile.git -t ubuntu:20.04git
