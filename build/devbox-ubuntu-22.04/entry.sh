#!/bin/bash

if [ $# -eq 0 ];
then
    # docker run -d
    service ssh start
    nohup bash -c "jupyter lab --allow-root --port=7878 --no-browser --notebook-dir=/opt " 2> /dev/null &
    sleep infinity
pelse
    # docker run -i CMD
    # docker run -it /bin/bash
    exec $@
fi  
