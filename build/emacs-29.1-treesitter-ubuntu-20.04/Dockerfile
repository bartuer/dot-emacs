FROM caapi/python:20.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential cmake libncurses-dev  && \
    apt-get clean && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists/* /tmp/* ~/*
RUN echo "install emacs"
# RUN /usr/bin/installemacs

ENV NVM_DIR="/root/.nvm"
RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash && \
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  && nvm install 6.0 && \
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  && nvm use 6.0 && npm install -g gulp 


# sudo echo 0 > /proc/sys/kernel/randomize_va_space; docker run --security-opt seccomp=unconfined;
# https://emacs.stackexchange.com/a/22667
RUN mkdir -p ~/etc && \
    cd ~/etc && \
    git clone https://github.com/bartuer/dot-emacs.git el && \
    mkdir -p ~/local/src && \
    cd ~/local/src && \
    curl -O https://ftp.gnu.org/gnu/emacs/emacs-25.3.tar.gz && \
    tar -xzf emacs-25.3.tar.gz && \
    cd ~/local/src/emacs-25.3 && \
    ./configure --prefix=/root/local --with-tiff=no --with-dbus --with-xft --with-xpm --with-xim --with-gconf --with-gnutls && \
    mkdir -p ~/local/share && \
    make -j && make install && \
    mkdir -p ~/local/bin/ && \
    cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin/pbcopy && \
    cp ~/etc/el/install/killemacs ~/local/bin/killemacs && \
    cp ~/etc/el/install/quote0 ~/local/bin/quote0 && \
    cp ~/etc/el/install/killemacs /usr/bin && \
    cp ~/etc/el/install/quote0 /usr/bin && \
    cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin/pbcopy

RUN mkdir -p ~/local/share/emacs && \
    ln -s ~/local/share/emacs/25.3 ~/local/share/emacs/current && \
    cd /root && \
    ln -s /root/etc/el/.emacs.el .emacs.el

RUN cd ~/etc/el/vendor && \
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  && nvm use 6.0 && npm install 

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN git config --global user.email "bartuer@bartuer.com"
RUN git config --global user.name "Bartuer Zhou"

# COPY .bashrc /root/.bashrc

RUN mkdir -p /ma/bazhou/local/src/
WORKDIR /ma/bazhou/local/src/
EXPOSE 22
ENTRYPOINT ["/bin/entry"]