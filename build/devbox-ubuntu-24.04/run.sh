docker stop -t 0 devbox_x86_64
docker rm dotnet9_x86_64
docker run  --platform linux/amd64 --name devbox_x86_64 -it --hostname amd64 -v /Users/bartuer:/opt caapi/amd64.devbox:24.04 /bin/bash
