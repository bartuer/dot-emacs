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
export PATH=~/local/bin:$PATH

alias e='~/local/bin/emacs --daemon -nw'
alias ed='~/local/bin/emacs --debug-init'
alias ec='~/local/bin/emacsclient -t'

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ─── LLM endpoints (hard-coded defaults) ────────────────
# Point every SDK (OpenAI / Anthropic / Ollama / Copilot CLI) at
# a local Ollama instance by default. Override at `docker run` time
# with -e OPENAI_BASE_URL=https://... etc.; the `:=` form preserves
# any value already inherited from the container environment.
: "${OPENAI_BASE_URL:=http://localhost:11434/v1}"
: "${OPENAI_API_KEY:=dummy}"
: "${ANTHROPIC_BASE_URL:=http://localhost:11434/anthropic}"
: "${ANTHROPIC_API_KEY:=dummy}"
: "${OLLAMA_HOST:=http://localhost:11434}"
: "${COPILOT_MODEL_BASE_URL:=http://localhost:11434}"
export OPENAI_BASE_URL OPENAI_API_KEY \
       ANTHROPIC_BASE_URL ANTHROPIC_API_KEY \
       OLLAMA_HOST COPILOT_MODEL_BASE_URL
