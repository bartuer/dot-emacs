# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoredups:ignorespace

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
#if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
#    . /etc/bash_completion
#fi


export NVM_VERSION=0.39.7
export NODE_VERSION=24.2.0
export NVM_DIR=/usr/local/nvm
export NODE_PATH=$NVM_DIR/v$NODE_VERSION/lib/node_modules
export RUSTUP_HOME=/root/.rustup
export CARGO_HOME=/root/.cargo
export UV_DIR=/root/.local

[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/
export PATH=~/local/bin:$CARGO_HOME/bin:$NVM_DIR/versions/node/v$NODE_VERSION/bin:$UV_DIR/bin:$PATH

[ -f /root/.local/.venv/bin/activate ] && source /root/.local/.venv/bin/activate

alias e='~/local/bin/emacs --daemon -nw'
alias ed='~/local/bin/emacs --debug-init'
alias ec='~/local/bin/emacsclient -t'

# >>> fleet provision >>>
export COPILOT_PROVIDER_TYPE="openai"
export COPILOT_PROVIDER_BASE_URL="http://127.0.0.1:11434/v1"
export COPILOT_PROVIDER_API_KEY="ollama"

alias ghe="env -u COPILOT_PROVIDER_TYPE -u COPILOT_PROVIDER_BASE_URL -u COPILOT_PROVIDER_API_KEY -u COPILOT_MODEL copilot --model gpt-5.6-sol --effort high --context long_context --allow-all --resume"

h() (
    local base_url="${COPILOT_PROVIDER_BASE_URL%/}"
    local catalog selected choice
    local -a models
    if ! catalog=$(curl -fsS --max-time 5 "${base_url}/models"); then
        echo "h: cannot load model catalog from ${base_url}/models" >&2
        return 1
    fi
    mapfile -t models < <(jq -r '.data[]?.id // empty' <<<"$catalog" | LC_ALL=C sort -u)
    if ((${#models[@]} == 0)); then
        echo "h: provider returned no models" >&2
        return 1
    fi
    if (($# > 0)) && [[ $1 != -* ]]; then
        selected=$1
        shift
    else
        printf 'Available L-server models:\n' >&2
        local i
        for i in "${!models[@]}"; do
            printf '  %d) %s\n' "$((i + 1))" "${models[i]}" >&2
        done
        read -r -p "Select model [1-${#models[@]}]: " choice
        if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#models[@]})); then
            echo "h: invalid model selection" >&2
            return 2
        fi
        selected=${models[choice - 1]}
    fi
    unset COPILOT_MODEL COPILOT_PROVIDER_MODEL_ID COPILOT_PROVIDER_WIRE_MODEL
    exec copilot --model "$selected" --allow-all "$@"
)
# <<< fleet provision <<<
# cli: fleet copilot session console (live /workspace/cluster/bin/cli-sessions.sh -> ~/local/bin/cli).
# FLEET_BOX: set per box by the roll-out; a fresh unpack derives it from
# fleet-ips.json .regions[].hostnames (container hostname = <host>ctr).
[ -n "${FLEET_BOX:-}" ] || FLEET_BOX=$(jq -r --arg h "${HOSTNAME%ctr}" '.regions[].hostnames // {}|to_entries[]|select((.value|ascii_downcase)==($h|ascii_downcase))|.key' /workspace/cluster/bin/fleet-ips.json 2>/dev/null | head -1)
export FLEET_BOX
# >>> fleet shell >>>   (managed by 39.shell.sh -- replaced whole on each roll-out)
_cli_complete() { COMPREPLY=($(compgen -W "all $(cut -d'|' -f1,2 ~/.copilot/sessions 2>/dev/null | tr '|' '\n' | sort -u)" -- "${COMP_WORDS[COMP_CWORD]}")); }
complete -F _cli_complete cli
# cps: live fleet console.  cli itself defaults CLI_REG_TTL=10 under watch (cluster d0ab1ed).
alias cps='watch -n 2 -c cli'
# t [name] [session]: attach-or-create tmux "<box>.<name>" running GHCP CLI.
# session (default = name) is resumed ONLY if it has events.jsonl -- a bare or unloadable
# --resume drops copilot into its interactive picker; otherwise start it fresh under that name.
# tmux gives a new session the SERVER's env, not this shell's -> forward COPILOT_* with -e.
# no args -> per-box defaults T_NAME/T_SID/T_ARGS (39.shell.sh converts an old `alias t=` into them).
alias t >/dev/null 2>&1 || function t {
    local v n s r d; local -a e=()
    if (($#)); then n=$1; s=${2:-$1}; else n=${T_NAME:-main}; s=${T_SID:-$n}; fi
    for v in ${!COPILOT_PROVIDER_@} COPILOT_MODEL; do [ -n "${!v:-}" ] && e+=(-e "$v=${!v}"); done
    for d in $(grep -lxF -e "id: $s" -e "name: $s" ~/.copilot/session-state/*/workspace.yaml 2>/dev/null); do
        d=${d%/*}; [ -s "$d/events.jsonl" ] && { r="--resume ${d##*/}"; break; }
    done
    [[ -z $r && $s =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]] && r="--session-id $s"
    tmux new -A -s "${FLEET_BOX}.$n" "${e[@]}" \
      "copilot --model ${COPILOT_MODEL:-claude-opus-5-5} --allow-all ${T_ARGS:-}--add-dir /workspace/cluster ${r:---name '$s'}"
}
# <<< fleet shell <<<
# Prefer the live cluster cli/room (cli needs orch-collect.py + room.sh beside it);
# the vendored ~/local/bin/cli is the fallback when /workspace/cluster is absent.
mkdir -p /root/local/bin; for _c in cli:cli-sessions.sh room:room.sh; do
    [ -x /workspace/cluster/bin/${_c#*:} ] && [ ! -L /root/local/bin/${_c%%:*} ] && ln -sfn /workspace/cluster/bin/${_c#*:} /root/local/bin/${_c%%:*}
done; unset _c
