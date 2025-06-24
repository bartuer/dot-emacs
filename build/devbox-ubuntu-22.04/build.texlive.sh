caffeinate docker buildx build -f Dockerfile.tex  --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.tex.base:22.04
docker stop -t 0 texbox
docker rm texbox
docker run --name texbox -it  caapi/arm64.tex.base:22.04 /bin/bash
docker cp texbox:/opt/arm64.dev.latex.22.04.tar.gz /Users/bartuer/Downloads
docker stop -t 0 texbox
docker rm texbox