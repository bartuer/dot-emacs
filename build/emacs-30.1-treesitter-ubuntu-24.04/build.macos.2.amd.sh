docker buildx build --progress=plain --platform linux/amd64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/amd64.emacs30.1:24.04
