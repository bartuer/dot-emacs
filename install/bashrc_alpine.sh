export TERM="xterm-256color"
export NVM_DIR="/home/bazhou/.nvm"
export PS1='${PWD} $ '
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

function post {
    curl -H "Content-Type: application/json" -d @-  $1
}

alias e='~/local/bin/emacs --daemon -nw -fg yellow'
alias ec='~/local/bin/emacsclient -t'
alias ed='~/local/bin/emacs --debug-init -nw -fg yellow'
alias ss='source ~/.bashrc'

export NPM_CONFIG_ELECTRON_MIRROR="https://npm.taobao.org/mirrors/electron/"
export GZIP_ENV="--rsyncable"
export PATH=~/.nvm:~/local/bin:~/scripts:$PATH
