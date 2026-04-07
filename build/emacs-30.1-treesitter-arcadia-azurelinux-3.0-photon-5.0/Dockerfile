# Arcadia (Azure Linux 3.0) Emacs builder
# Base: mcr.microsoft.com/officepy/codeexecutionjupyterext1
#
# Pre-installed in base: gcc 13.2.0, g++, make, tar, curl, zlib-devel,
#   pkgconf, ncurses-libs, node v22, python 3.12
# No libgccjit available → native compilation disabled.
# No tree-sitter package → build from source.

FROM mcr.microsoft.com/officepy/codeexecutionjupyterext1

WORKDIR /opt

# Install only what's missing for the Emacs build.
# gcc, make, tar, curl, zlib-devel, pkgconf already in base.
RUN tdnf install -y \
        glibc-devel \
        kernel-headers \
        binutils \
        git \
        autoconf \
        texinfo \
        ncurses-devel \
        gnutls-devel \
        jansson-devel \
        sqlite-devel \
    && tdnf clean all

# Build and install tree-sitter from source (no tdnf package available)
# Pin to v0.22.6 — Emacs 30.1 expects ts_language_version (removed in 0.24+)
RUN git clone --depth 1 --branch v0.22.6 https://github.com/tree-sitter/tree-sitter.git \
    && cd /opt/tree-sitter \
    && make -j$(nproc) \
    && make install \
    && rm -rf /opt/tree-sitter

ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/local/lib/pkgconfig

# Build Emacs 30.1
RUN mkdir -p /root/local/src \
    && cd /root/local/src \
    && curl -fsSLO https://ftp.gnu.org/gnu/emacs/emacs-30.1.tar.gz \
    && tar -xzf emacs-30.1.tar.gz \
    && cd emacs-30.1 \
    && ./autogen.sh

# No --with-native-compilation (libgccjit not available on Azure Linux 3.0).
# Tree-sitter enabled via source-built lib above.
RUN cd /root/local/src/emacs-30.1 \
    && ./configure \
        --prefix=/root/local \
        --with-tree-sitter \
        --with-gnutls \
        --with-json \
        --without-native-compilation \
        --without-dbus \
        --without-xft --without-xpm --without-xim \
        --without-gconf --without-mailutils \
        --without-jpeg --without-tiff --without-gif \
        --without-png --without-rsvg --without-lcms2 \
        --without-libsystemd --without-cairo --without-xml2 \
        --without-native-image-api --without-harfbuzz \
        --without-libotf --without-toolkit-scroll-bars \
        --without-xaw3d --without-xdbe --without-gpm \
        --without-gsettings --without-selinux \
        --without-libgmp --without-kerberos --without-kerberos5 \
        --without-hesiod \
        --with-sound=no \
        --with-x-toolkit=no \
        --with-x=no \
        CFLAGS=-O3 \
    && make -j$(nproc) \
    && make install

# Symlink for convenience
RUN mkdir -p /root/local/share/emacs \
    && ln -sf /root/local/share/emacs/30.1 /root/local/share/emacs/current

# Bring in dot-emacs config and helper scripts
RUN git config --global --add safe.directory /root/etc/el \
    && mkdir -p /root/etc \
    && cd /root/etc \
    && git clone https://github.com/bartuer/dot-emacs.git el \
    && mkdir -p /root/local/bin \
    && cp /root/etc/el/install/pbcopy.xlicp.sh /root/local/bin/pbcopy \
    && cp /root/etc/el/install/killemacs /root/local/bin/killemacs \
    && cp /root/etc/el/install/quote0 /root/local/bin/quote0 \
    && cp /root/etc/el/install/killemacs /usr/bin \
    && cp /root/etc/el/install/quote0 /usr/bin \
    && ln -sf /root/etc/el/.emacs.el /root/.emacs.el

RUN mkdir -p /root/.emacs.d/tree-sitter/bin

# Compile tree-sitter grammar shared objects using Emacs batch mode.
# The grammars are defined in the dot-emacs config (tree-sitter/treesit-compile.el).
# Emacs 30.1 treesit-install-language-grammar needs: gcc, git, libtree-sitter — all present.
RUN /root/local/bin/emacs --batch \
    --eval '(setq treesit-extra-load-path (list "/root/.emacs.d/tree-sitter/"))' \
    -l /root/etc/el/tree-sitter/treesit-compile.el \
    -f do-treesit-compile

# Entry point and shell config
COPY entry.sh /bin/entry
RUN chmod +x /bin/entry

COPY .bashrc /root/.bashrc

# Packaging scripts (copied in by context)
COPY amd64.tar.list /opt/amd64.tar.list
COPY tar.sh /opt/tar.sh
RUN chmod +x /opt/tar.sh

ENTRYPOINT ["/bin/entry"]
CMD ["/bin/sh", "-lc", "echo built"]
