#!/bin/bash

if [ $# -eq 0 ];
then
    # docker run -d
    service ssh start
    nohup bash -c "source /opt/local/src/env.sh; source /root/.local/.venv/bin/activate; /root/.local/.venv/bin/jupyter lab --allow-root --Application.log_level=DEBUG --ip=0.0.0.0 --port=7878 --no-browser --notebook-dir=/opt " 2> /var/log/jupyter.log &
    sleep infinity
pelse
    # docker run -i CMD
    # docker run -it /bin/bash
    exec $@
fi  
