#!/bin/bash
# Host-safe installer for the arm64 devbox tarballs.
#
# The tarballs are extracted with `tar -C /` on a LIVE host. They intentionally
# do NOT carry server SSH identity/config (sshd_config, ssh_config, moduli,
# ssh_host_*, pam.d/sshd) nor /etc/passwd, so extraction cannot break host SSH.
#
# The dev public key ships as a STAGING file /root/.ssh/authorized_keys.devbox
# (never authorized_keys directly), so `tar -C /` cannot overwrite an existing
# host authorized_keys. This script then MERGES + de-dups it into the live file.
set -e

tar zxf arm64.emacs30.1_24.04.tar.gz -C /
tar zxf arm64.dev.base.24.04.tar.gz -C /
# Optional per-language dev packs (uncomment those you built):
# tar zxf arm64.dev.cc.24.04.tar.gz -C /
# tar zxf arm64.dev.py.24.04.tar.gz -C /
# tar zxf arm64.dev.rs.24.04.tar.gz -C /
# tar zxf arm64.dev.js.24.04.tar.gz -C /
# tar zxf arm64.dev.cs.24.04.tar.gz -C /

# --- append-safe authorized_keys merge (never clobber an existing host key) ---
if [ -f /root/.ssh/authorized_keys.devbox ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    cat /root/.ssh/authorized_keys.devbox >> /root/.ssh/authorized_keys
    # de-dup while preserving order (keeps any pre-existing operator keys)
    awk '!seen[$0]++' /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.merged
    mv /root/.ssh/authorized_keys.merged /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    rm -f /root/.ssh/authorized_keys.devbox
fi

ldconfig
source ~/.bashrc
