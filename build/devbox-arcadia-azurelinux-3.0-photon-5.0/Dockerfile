# Arcadia (Azure Linux 3.0) dev.base builder
# Base: mcr.microsoft.com/officepy/codeexecutionjupyterext1
#
# Pre-installed in base: curl, tar, findutils, gcc, make, node v22, python 3.12
# Install only missing baseline tools for dev workflow.

FROM mcr.microsoft.com/officepy/codeexecutionjupyterext1

ARG RIPGREP_VERSION=14.1.1
ARG RIPGREP_SHA256=4cf9f2741e6c465ffdb7c26f38056a59e2a2544b51f7cc128ef28337eeae4d8e
ARG PARALLEL_VERSION=20250622
ARG PARALLEL_SHA256=69f578cf11f1b124ba3c2b673a16641debe63aeb3d2ac4cec5ad65f8a53d489b

# Install missing baseline tools.
# curl, tar, findutils, ca-certificates already in base.
RUN tdnf install -y \
        git \
        openssh-clients \
        openssh-server \
        glibc-lang \
        file \
        jq-1.7.1-8.azl3 \
        rsync-3.4.3-1.azl3 \
    && (tdnf install -y glibc-i18n || true) \
    && tdnf clean all

# ripgrep is not available in the Azure Linux repositories. Install its
# upstream static-musl release and verify the archive before extraction.
RUN set -eu; \
    archive="ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz"; \
    curl -fsSLO "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/${archive}"; \
    printf '%s  %s\n' "$RIPGREP_SHA256" "$archive" | sha256sum -c -; \
    tar xzf "$archive"; \
    install -m 0755 "ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg" /usr/local/bin/rg; \
    rm -rf "$archive" "ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl"

# GNU parallel is also absent from the repositories. Its command is a
# self-contained Perl script, so install only that command from the verified
# upstream release rather than adding a build toolchain.
RUN set -eu; \
    archive="parallel-${PARALLEL_VERSION}.tar.bz2"; \
    curl -fsSLO "https://ftp.gnu.org/gnu/parallel/${archive}"; \
    printf '%s  %s\n' "$PARALLEL_SHA256" "$archive" | sha256sum -c -; \
    tar xjf "$archive"; \
    install -m 0755 "parallel-${PARALLEL_VERSION}/src/parallel" /usr/local/bin/parallel; \
    rm -rf "$archive" "parallel-${PARALLEL_VERSION}"

# Language servers for Emacs eglot integration.
#   - jedi-language-server                    : python-mode / python-ts-mode (PyPI)
#   - typescript-language-server + typescript : typescript-mode / typescript-ts-mode (npm)
# Base image already ships python3.12 (at /app/officepy/bin) and node v22 with
# global npm at /usr (so npm-global bins land in /usr/bin, already on PATH).
# csharp-ls intentionally omitted (requires .NET runtime, not in this devbox).
# These installs land OUTSIDE the rpm db, so tar.sh must explicitly include
# their files when packaging the offline tarball — see tar.sh.
RUN /app/officepy/bin/pip install --no-cache-dir jedi-language-server \
 && npm install -g --no-audit --no-fund typescript typescript-language-server

# Default UTF-8 locale for shells and tools.
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Git config defaults
RUN git config --global --add safe.directory /root/etc/el \
    && git config --global core.pager cat

# SSH setup — pre-generate host keys so they are stable across restarts
# and included in the tarball (no need for ssh-keygen -A at runtime).
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh \
    && ssh-keygen -A

# Custom sshd config (PermitRootLogin, pubkey auth, hardened ciphers)
COPY sshd_config /etc/ssh/sshd_config

# Entry point and shell config
COPY entry.sh /bin/entry
RUN chmod +x /bin/entry

COPY .bashrc /root/.bashrc
COPY config /root/.ssh/config
COPY authorized_keys /root/.ssh/authorized_keys

# Packaging scripts
COPY tar.sh /opt/tar.sh
RUN chmod +x /opt/tar.sh

ENTRYPOINT ["/bin/entry"]
CMD ["/bin/sh", "-lc", "echo built"]
