
export NVM_DIR="/home/bazhou/.nvm" 
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

function post {
    curl -H "Content-Type: application/json" -d @-  $1
}

alias g='gulp'
alias e='~/local/bin/emacs-24.5 --daemon -nw -fg yellow'
alias ec='~/local/bin/emacsclient -t'
alias ed='~/local/bin/emacs-24.5 --debug-init -nw -fg yellow'
alias ss='source ~/.bashrc'

export NPM_CONFIG_ELECTRON_MIRROR="https://npm.taobao.org/mirrors/electron/"
export GZIP_ENV="--rsyncable"
export PATH=~/.nvm;~/local/bin:~/scripts:$PATH
