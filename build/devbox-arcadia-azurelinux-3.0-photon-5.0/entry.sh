#!/bin/bash

if [ $# -eq 0 ];
then
    # docker run -d
    # Host keys are pre-generated during build and included in the tarball.
    # Only regenerate if missing (e.g. fresh base image without tarball).
    [ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -A
    /usr/sbin/sshd
    sleep infinity
else
    # docker run -i CMD
    # docker run -it /bin/bash
    exec $@
fi  
