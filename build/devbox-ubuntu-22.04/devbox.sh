docker stop -t 0 devbox
docker rm devbox
docker run --name devbox --hostname devbox -d --ulimit nofile=65535:65535 -p 3333:22 -p 7878:7878 -p 8000:8000 -p 9000:9000 -v /Users/bartuer:/opt -w /opt/Downloads caapi/arm64.devbox.commit:22.04 /bin/entry

