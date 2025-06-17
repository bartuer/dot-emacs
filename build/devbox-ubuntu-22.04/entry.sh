#!/bin/bash

if [ $# -eq 0 ];
then
    # docker run -d
    service ssh start
    # nohup bash -c "source /opt/local/src/env.sh; jupyter lab --allow-root --port=8787 --no-browser --notebook-dir=/src " 2> /dev/null &
    sleep infinity
pelse
    # docker run -i CMD
    # docker run -it /bin/bash
    exec $@
fi  
