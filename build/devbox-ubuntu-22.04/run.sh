docker stop -t 0 devbox
docker rm devbox
docker run --name devbox -it  caapi/arm64.devbox:22.04 /bin/bash
# docker run --name devbox -it  -v /Users/bartuer:/opt ubuntu:22.04
