FROM ubuntu:20.04

WORKDIR /opt

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && DEBIAN_FRONTEND=noninteractive \
        && apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common \
        build-essential \
        autoconf \
        pkg-config \
        git \
        cmake \
        libncurses-dev libncurses5-dev \
        libjansson4 libjansson-dev \
        zlib1g-dev \
        libgnutls28-dev \
        libsqlite3-dev \
        aspell aspell-en \
        r-base \
        sbcl \
        xclip
        
RUN add-apt-repository ppa:ubuntu-toolchain-r/ppa \
        && apt-get update  && DEBIAN_FRONTEND=noninteractive \
        && apt-get install -y gcc-10 libgccjit0 libgccjit-10-dev

ENV CC="gcc-10"

ENV NVM_DIR="/root/.nvm"
RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash && \
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  && nvm install 6.0 && \
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  && nvm use 6.0 

RUN git clone https://github.com/tree-sitter/tree-sitter.git \
    && cd /opt/tree-sitter \
    && make -j \
    && make install

# sudo echo 0 > /proc/sys/kernel/randomize_va_space; docker run --security-opt seccomp=unconfined;
# https://emacs.stackexchange.com/a/22667
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/local/lib/pkgconfig 

RUN mkdir -p ~/local/src && \
    cd ~/local/src && \
    curl -O https://ftp.gnu.org/gnu/emacs/emacs-29.1.tar.gz && \
    tar -xzf emacs-29.1.tar.gz && \
    cd ~/local/src/emacs-29.1 && \
    ./autogen.sh

RUN cd ~/local/src/emacs-29.1 && \
    ./configure --prefix=/root/local --with-native-compilation --with-tree-sitter --with-tiff=no --without-dbus --without-xft --without-xpm --without-xim --without-gconf --with-gnutls --with-json --without-mailutils --without-jpeg --without-tiff --without-gif --without-png --without-rsvg --without-lcms2 --without-libsystemd --without-cairo --without-xml2 --without-native-image-api --without-xft --without-harfbuzz --without-libotf --without-toolkit-scroll-bars --without-xaw3d --without-xim --without-xdbe --without-gpm --without-gsettings --without-selinux --without-libgmp --without-kerberos --without-kerberos5 --without-hesiod --with-sound=no --with-x-toolkit=no --with-x=no CFLAGS=-O3 && \
    mkdir -p ~/local/share && \
    make -j && make install && \
    mkdir -p ~/local/bin/

# RUN mkdir -p ~/etc
# COPY ./el /root/etc/el

RUN echo "repo 84dc050"
RUN mkdir -p ~/etc && \
    cd ~/etc && \
    git clone https://github.com/bartuer/dot-emacs.git el && \
    cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin/pbcopy && \
    cp ~/etc/el/install/killemacs ~/local/bin/killemacs && \
    cp ~/etc/el/install/quote0 ~/local/bin/quote0 && \
    cp ~/etc/el/install/killemacs /usr/bin && \
    cp ~/etc/el/install/quote0 /usr/bin && \
    cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin/pbcopy

RUN mkdir -p ~/local/share/emacs && \
    ln -s ~/local/share/emacs/29.1 ~/local/share/emacs/current && \
    cd /root && \
    ln -s /root/etc/el/.emacs.el .emacs.el

COPY .bashrc /root/.bashrc