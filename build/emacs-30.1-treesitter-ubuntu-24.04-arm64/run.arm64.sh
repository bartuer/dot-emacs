docker stop -t 0 emacs30.1
docker rm emacs30.1
docker run  --platform linux/arm64 --name emacs30.1 -d --hostname noble -p 2222:22 -v /Users/bartuer:/opt caapi/arm64.emacs30.1:24.04
