# Arcadia (Azure Linux 3.0) dev.base builder
# Base: mcr.microsoft.com/officepy/codeexecutionjupyterext1
#
# Pre-installed in base: curl, tar, findutils, gcc, make, node v22, python 3.12
# Install only missing baseline tools for dev workflow.

FROM mcr.microsoft.com/officepy/codeexecutionjupyterext1

# Install missing baseline tools.
# curl, tar, findutils, ca-certificates already in base.
RUN tdnf install -y \
        git \
        openssh-clients \
        openssh-server \
        file \
    && tdnf clean all

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

# Packaging scripts
COPY tar.sh /opt/tar.sh
RUN chmod +x /opt/tar.sh

ENTRYPOINT ["/bin/entry"]
CMD ["/bin/sh", "-lc", "echo built"]
