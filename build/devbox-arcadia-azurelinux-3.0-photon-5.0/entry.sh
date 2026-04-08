#!/bin/bash

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
