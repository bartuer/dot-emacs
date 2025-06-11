docker stop -t 0 devbox
docker rm devbox
docker run  --name devbox -it  -v /Users/bartuer:/opt ubuntu:22.04
