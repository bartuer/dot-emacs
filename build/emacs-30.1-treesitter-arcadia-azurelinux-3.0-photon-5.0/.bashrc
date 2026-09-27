# ~/.bashrc: executed by bash(1) for non-login shells.

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

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color) color_prompt=yes;;
esac

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Alias definitions.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/
# /app/officepy/bin exposes python3.12 + pip + jupyter + pip-installed LSPs
# (jedi-language-server) so eglot/emacs subprocesses can find them.
export PATH=~/local/bin:/app/copilot/bin:/app/node_modules/.bin:/app/officepy/bin:$PATH

alias e='~/local/bin/emacs --daemon -nw'
alias ed='~/local/bin/emacs --debug-init'
alias ec='~/local/bin/emacsclient -t'

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

                                                                                                   
                                                                                                   
# GHCP CLI clipboard shim (no-X path; writes to ~/.clipboard)
export NODE_OPTIONS="--require /root/.copilot-clipboard-shim.js ${NODE_OPTIONS:-}"

. "$HOME/.cargo/env"

# added by scripts/env_check.sh -- ssg -- .venv on PATH
# interactive convenience ONLY: skills/scripts call
# .venv/bin/python explicitly and do not rely on this.
export PATH="/workspace/OfficeAgent/agents/ssg-agent/.venv/bin:$PATH"

# Skip the ADO device-flow yarn plugin locally (isInsidePipeline()==true);
# auth comes from npmAuthToken in ~/.yarnrc.yml instead.
export AGENT_ID="${AGENT_ID:-local-pat-bypass}"

# 1. Set the provider type to 'openai' (Ollama uses the OpenAI-compatible API)
export COPILOT_PROVIDER_TYPE="openai"
                                                                                                   
# 2. Point to your local Ollama endpoint
export COPILOT_PROVIDER_BASE_URL="http://host.docker.internal:11434/v1"
                                                                                                   
# 3. Specify the model name (as seen in 'ollama list')
export COPILOT_MODEL="claude-opus-5-5"
                                                                                                   
# 4. Use a placeholder API key (Ollama doesn't require one, but the CLI expects a string)
export COPILOT_PROVIDER_API_KEY="ollama"
                                                                                                   
# GHCP CLI clipboard shim (no-X path; writes to ~/.clipboard)
export NODE_OPTIONS="--require /root/.copilot-clipboard-shim.js ${NODE_OPTIONS:-}"

touch /root/.copilot-clipboard-shim.js
alias harness="copilot --allow-all --resume --autopilot"
alias h="copilot --allow-all --resume --autopilot --model claude-opus-5-5"

# cli: fleet copilot session console (install/cli -> ~/local/bin/cli).
# >>> fleet shell >>>   (managed by 39.shell.sh -- replaced whole on each roll-out)
_cli_complete() { COMPREPLY=($(compgen -W "all $(cut -d'|' -f1,2 ~/.copilot/sessions 2>/dev/null | tr '|' '\n' | sort -u)" -- "${COMP_WORDS[COMP_CWORD]}")); }
complete -F _cli_complete cli
# t [name] [copilot-session-id]: attach-or-create tmux "<box>.<name>" running GHCP CLI (--resume)
alias t >/dev/null 2>&1 || function t {
    tmux new -A -s "${FLEET_BOX}.${1:-main}" \
      "copilot --model ${COPILOT_MODEL:-claude-opus-5-5} --allow-all --add-dir /workspace/cluster --resume ${2:-}"
}
# <<< fleet shell <<<
# Prefer the live cluster cli/room (cli needs orch-collect.py + room.sh beside it);
# the vendored ~/local/bin/cli is the fallback when /workspace/cluster is absent.
for _c in cli:cli-sessions.sh room:room.sh; do
    [ -x /workspace/cluster/bin/${_c#*:} ] && [ ! -L /root/local/bin/${_c%%:*} ] && ln -sfn /workspace/cluster/bin/${_c#*:} /root/local/bin/${_c%%:*}
done; unset _c
