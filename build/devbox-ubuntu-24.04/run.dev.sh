docker stop -t 0 dev
docker rm dev
docker run  --platform linux/amd64 --name dev -it --hostname dev -v /Users/bartuer:/opt caapi/amd64.dev:24.04 /bin/bash
