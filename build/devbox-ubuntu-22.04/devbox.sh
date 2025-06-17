docker stop -t 0 devbox
docker rm devbox
docker run --name devbox --hostname devbox -d -p 3333:22 -p 7878:8787 -v /Users/bartuer:/opt -w /opt/Downloads caapi/arm64.devbox:22.04

