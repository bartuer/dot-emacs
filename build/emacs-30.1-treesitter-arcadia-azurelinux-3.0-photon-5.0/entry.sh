#!/bin/bash

# Ensure tree-sitter grammar modules can dlopen libtree-sitter.so.0
# regardless of how this container is entered (docker run CMD, sshd
# children, `docker exec`, etc.). /etc/ld.so.conf.d/local.conf covers
# the dynamic linker; this covers any tooling that still consults
# LD_LIBRARY_PATH.
export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"

if [ $# -eq 0 ];
then
    # docker run -d
    if command -v sshd >/dev/null 2>&1; then
        [ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -A
        # sshd needs a privilege-separation user and directory
        id sshd >/dev/null 2>&1 || useradd -r -d /var/lib/sshd -s /sbin/nologin sshd 2>/dev/null
        mkdir -p /var/lib/sshd /var/empty/sshd
        /usr/sbin/sshd
    fi
    sleep infinity
else
    # docker run -i CMD
    # docker run -it /bin/bash
    exec $@
fi  
