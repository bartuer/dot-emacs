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
#
# Extra packages for libvterm + emacs-libvterm dynamic module:
#   cmake, libtool   — build system for libvterm + emacs-libvterm
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
        aspell \
        cmake \
        libtool \
    && tdnf clean all

# Build aspell English dictionary from source (no aspell-en package in Azure Linux 3.0).
# The dict configure script uses `which` to find aspell/prezip — not available in base.
# Set ASPELL and PREZIP explicitly so configure/make succeed.
RUN cd /opt \
    && curl -fsSL https://ftp.gnu.org/gnu/aspell/dict/en/aspell6-en-2020.12.07-0.tar.bz2 | tar xj \
    && cd aspell6-en-2020.12.07-0 \
    && ASPELL=/usr/bin/aspell PREZIP=/usr/bin/prezip-bin ./configure \
    && make ASPELL=/usr/bin/aspell PREZIP=/usr/bin/prezip-bin \
    && make install \
    && rm -rf /opt/aspell6-en-2020.12.07-0

# Build and install tree-sitter from source (no tdnf package available)
# Pin to v0.22.6 — Emacs 30.1 expects ts_language_version (removed in 0.24+)
RUN git clone --depth 1 --branch v0.22.6 https://github.com/tree-sitter/tree-sitter.git \
    && cd /opt/tree-sitter \
    && make -j$(nproc) \
    && make install \
    && rm -rf /opt/tree-sitter

ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:/usr/local/lib/pkgconfig

# Build and install libvterm from source (no tdnf package available).
# Pin to 0.3.3 — the release emacs-libvterm CI uses as of 2026.
# Installs to /usr/local (lib + include + pkgconfig), which is already
# on LD_LIBRARY_PATH and PKG_CONFIG_PATH (set above).
RUN cd /opt \
    && curl -fsSLO https://www.leonerd.org.uk/code/libvterm/libvterm-0.3.3.tar.gz \
    && tar xzf libvterm-0.3.3.tar.gz \
    && cd libvterm-0.3.3 \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && cd /opt \
    && rm -rf libvterm-0.3.3 libvterm-0.3.3.tar.gz

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
        --with-modules \
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

# Build akermu/emacs-libvterm dynamic module against system libvterm.
# The module (vterm-module.so) + elisp (vterm.el) are vendored into
# /root/etc/el/vendor/vterm/ so the dot-emacs config can load them.
# Must run AFTER dot-emacs is cloned (vendor/ dir lives inside it) and
# AFTER Emacs is installed (emacs-libvterm's CMake locates emacs via
# EMACS_SOURCE for the module headers).
# Pin to current master HEAD (2026-04) for reproducibility.
ENV EMACS_LIBVTERM_COMMIT=54c29d14bca05bdd8ae60cda01715d727831e3f9
RUN cd /opt \
    && git clone https://github.com/akermu/emacs-libvterm.git vterm-src \
    && cd vterm-src \
    && git checkout "$EMACS_LIBVTERM_COMMIT" \
    && mkdir build && cd build \
    && cmake -DUSE_SYSTEM_LIBVTERM=yes \
             -DEMACS_SOURCE=/root/local/src/emacs-30.1 \
             .. \
    && make -j$(nproc) \
    && mkdir -p /root/etc/el/vendor/vterm \
    && cp ../vterm.el ../vterm-module.so /root/etc/el/vendor/vterm/ \
    && cd /opt && rm -rf vterm-src

RUN mkdir -p /root/.emacs.d/tree-sitter/bin

# Write BUNDLE-VERSION so tree-sitter-langs skips the GitHub download
# (no DNS inside the container). The version must match the constant in
# vendor/tree-sitter-langs/tree-sitter-langs-build.el.
RUN echo -n "0.12.276" > /root/.emacs.d/tree-sitter/bin/BUNDLE-VERSION

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
