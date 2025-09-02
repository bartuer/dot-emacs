# caffeinate docker buildx build --progress=plain --platform linux/amd64 --build-arg https_proxy=socks5://host.docker.internal:8080 . -t caapi/amd64.devbox.build:24.04
docker stop -t 0 devbox_x86_64
docker rm devbox_x86_64
docker run --platform linux/amd64 --name devbox_x86_64 -d  caapi/amd64.devbox.build:24.04 /bin/bash
docker cp devbox_x86_64:/opt/amd64.dev.js.24.04.tar.gz /Users/bartuer/Downloads
docker cp devbox_x86_64:/opt/amd64.dev.rs.24.04.tar.gz /Users/bartuer/Downloads
docker cp devbox_x86_64:/opt/amd64.dev.cc.24.04.tar.gz /Users/bartuer/Downloads
docker cp devbox_x86_64:/opt/amd64.dev.py.24.04.tar.gz /Users/bartuer/Downloads
docker cp devbox_x86_64:/opt/amd64.dev.cs.24.04.tar.gz /Users/bartuer/Downloads
docker cp devbox_x86_64:/opt/amd64.dev.base.24.04.tar.gz /Users/bartuer/Downloads
docker stop -t 0 devbox_x86_64
docker rm devbox_x86_64
docker run  --platform linux/amd64 --name devbox_x86_64 --hostname devbox86  -it -p 4444:22 -p 8686:7878 -v /Users/bartuer:/opt -w /opt/Downloads ubuntu:24.04 /bin/bash
