caffeinate docker buildx build --progress=plain --platform linux/arm64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/arm64.devbox.build:22.04
docker stop -t 0 devbox
docker rm devbox
docker run --name devbox -d  caapi/arm64.devbox.build:22.04 /bin/bash
docker cp devbox:/opt/arm64.dev.js.22.04.tar.gz /Users/bartuer/Downloads
docker cp devbox:/opt/arm64.dev.rs.22.04.tar.gz /Users/bartuer/Downloads
docker cp devbox:/opt/arm64.dev.cc.22.04.tar.gz /Users/bartuer/Downloads
docker cp devbox:/opt/arm64.dev.py.22.04.tar.gz /Users/bartuer/Downloads
docker cp devbox:/opt/arm64.dev.base.22.04.tar.gz /Users/bartuer/Downloads
docker stop -t 0 devbox
docker rm devbox
docker run --name devbox --hostname devbox -it -p 3333:22 -v /Users/bartuer:/opt -w /opt/Downloads ubuntu:22.04 /bin/sh

