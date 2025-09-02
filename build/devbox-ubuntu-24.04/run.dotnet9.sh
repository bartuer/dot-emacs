docker stop -t 0 dotnet9
docker rm dotnet9
docker run  --platform linux/amd64 --name dotnet9 -it --hostname dotnet -v /Users/bartuer:/opt caapi/amd64.dotnet9:24.04 /bin/bash
