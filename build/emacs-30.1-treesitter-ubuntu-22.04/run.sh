docker stop -t 0 emacs30.1
docker rm emacs30.1
docker run  --name emacs30.1 -d --hostname jellyfish -p 2222:22 -v /Users/bartuer:/opt caapi/arm64.emacs30.1:22.04 
