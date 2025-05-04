docker buildx build --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.emacs29.1:20.04
# docker build . -f Dockerfile.git -t ubuntu:20.04git
