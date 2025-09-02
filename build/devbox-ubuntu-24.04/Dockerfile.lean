FROM ubuntu:24.04 AS dotnet_installer

ENV \
    APP_UID=1654 \
    ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_RUNNING_IN_CONTAINER=true

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        libatomic1 \
        wget \
        ca-certificates \
        libc6 \
        libgcc-s1 \
        libicu74 \
        libssl3t64 \
        libstdc++6 \
        tzdata \
        tzdata-legacy \
        parallel \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user and group
RUN groupadd \
        --gid=$APP_UID \
        app \
    && useradd --no-log-init \
        --uid=$APP_UID \
        --gid=$APP_UID \
        --create-home \
        app

ENV \
    DOTNET_VERSION=9.0.8 \
    ASPNET_VERSION=9.0.8 \
    DOTNET_SDK_VERSION=9.0.304 \
    DOTNET_DIR=/usr/share/dotnet \
    DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    DOTNET_NOLOGO=true \
    DOTNET_USE_POLLING_FILE_WATCHER=true \
    NUGET_XMLDOC_MODE=skip

RUN curl --fail --show-error --location \
        --remote-name https://builds.dotnet.microsoft.com/dotnet/Runtime/$DOTNET_VERSION/dotnet-runtime-$DOTNET_VERSION-linux-x64.tar.gz \
        --remote-name https://builds.dotnet.microsoft.com/dotnet/checksums/$DOTNET_VERSION-sha.txt \
    && sed -i 's/\r$//' $DOTNET_VERSION-sha.txt \
    && sha512sum -c $DOTNET_VERSION-sha.txt --ignore-missing \
    && mkdir --parents $DOTNET_DIR \
    && tar --gzip --extract --no-same-owner --file dotnet-runtime-$DOTNET_VERSION-linux-x64.tar.gz --directory $DOTNET_DIR \
    && rm \
        dotnet-runtime-$DOTNET_VERSION-linux-x64.tar.gz \
        $DOTNET_VERSION-sha.txt

RUN ASPNETCORE_VERSION=9.0.8 \
    && curl --fail --show-error --location \
        --remote-name https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/$ASPNETCORE_VERSION/aspnetcore-runtime-$ASPNETCORE_VERSION-linux-x64.tar.gz \
        --remote-name https://builds.dotnet.microsoft.com/dotnet/checksums/$ASPNETCORE_VERSION-sha.txt \
    && sed -i 's/\r$//' $ASPNETCORE_VERSION-sha.txt \
    && sha512sum -c $ASPNETCORE_VERSION-sha.txt --ignore-missing \
    && mkdir --parents $DOTNET_DIR \
    && tar --gzip --extract --no-same-owner --file aspnetcore-runtime-$ASPNETCORE_VERSION-linux-x64.tar.gz --directory $DOTNET_DIR ./shared/Microsoft.AspNetCore.App \
    && rm \
        aspnetcore-runtime-$ASPNETCORE_VERSION-linux-x64.tar.gz \
        $ASPNETCORE_VERSION-sha.txt

RUN curl --fail --show-error --location \
        --remote-name https://builds.dotnet.microsoft.com/dotnet/Sdk/$DOTNET_SDK_VERSION/dotnet-sdk-$DOTNET_SDK_VERSION-linux-x64.tar.gz \
        --remote-name https://builds.dotnet.microsoft.com/dotnet/checksums/$DOTNET_VERSION-sha.txt \
    && sed -i 's/\r$//' $DOTNET_VERSION-sha.txt \
    && sha512sum -c $DOTNET_VERSION-sha.txt --ignore-missing \
    && mkdir --parents $DOTNET_DIR \
    && mkdir --parents /dotnet \
    && tar --gzip --extract --no-same-owner --file dotnet-sdk-$DOTNET_SDK_VERSION-linux-x64.tar.gz --directory $DOTNET_DIR ./packs ./sdk ./sdk-manifests ./templates ./LICENSE.txt ./ThirdPartyNotices.txt \
    && rm \
        dotnet-sdk-$DOTNET_SDK_VERSION-linux-x64.tar.gz \
        $DOTNET_VERSION-sha.txt

RUN ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet
RUN dotnet help

# Install PowerShell global tool
ENV \
    POWERSHELL_VERSION=7.5.2 \
    POWERSHELL_PATH=$DOTNET_DIR/powershell \
    POWERSHELL_DISTRIBUTION_CHANNEL=PSDocker-DotnetSDK-Ubuntu-24.04

RUN curl --fail --show-error --location --output PowerShell.Linux.x64.$POWERSHELL_VERSION.nupkg https://powershellinfraartifacts-gkhedzdeaghdezhr.z01.azurefd.net/tool/$POWERSHELL_VERSION/PowerShell.Linux.x64.$POWERSHELL_VERSION.nupkg \
    && mkdir --parents $POWERSHELL_PATH \
    && dotnet tool install --add-source / --tool-path $POWERSHELL_PATH --version $POWERSHELL_VERSION PowerShell.Linux.x64 \
    && ln -s $POWERSHELL_PATH/pwsh /usr/bin/pwsh \
    && chmod 755 $POWERSHELL_PATH/pwsh \
    && dotnet nuget locals all --clear \
    && rm PowerShell.Linux.x64.$POWERSHELL_VERSION.nupkg 

RUN pwsh --version
# Install CSharp Language server tool
ENV \
    CSHARP_LS_PATH=$DOTNET_DIR/csharpls

RUN mkdir --parents $CSHARP_LS_PATH \
    && dotnet tool install --tool-path=$CSHARP_LS_PATH csharp-ls \
    && ln -s $CSHARP_LS_PATH/csharp-ls /usr/bin/csharp-ls \
    && chmod 755 $CSHARP_LS_PATH/csharp-ls \
    && dotnet nuget locals all --clear

RUN csharp-ls --version

CMD ["/bin/bash"]