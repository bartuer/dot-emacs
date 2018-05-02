
export NVM_DIR="/home/bazhou/.nvm" 
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

function httpserver {
    docker run --rm -p $2:80 -v $1:/opt --restart always -d busybox httpd -f -h /opt -p 80
}

function post {
    curl -H "Content-Type: application/json" -d @-  $1
}

function tojson {
    awk '{print $1, $2}' - |jq -R .|jq  -s '.' --indent 0
}

alias g='gulp'
alias e='~/local/bin/emacs-25.3 --daemon '
alias ec='~/local/bin/emacsclient -t'
alias ef="~/local/bin/emacscleint -c"
alias ed='~/local/bin/emacs-25.3 --debug-init '
alias ss='source ~/.bashrc'

export NPM_CONFIG_ELECTRON_MIRROR="https://npm.taobao.org/mirrors/electron/"
export GZIP_ENV="--rsyncable"
export PATH=~/.nvm:~/local/bin:~/scripts:$PATH
