#!/bin/sh

alias ls="ls --color=always --group-directories-first"
# alias ec="tmux select-window -t 2 && emacsclient"
# alias ta="tmux attach"
alias ll="ls -lAh"
alias du1="du --max-depth=1"
alias grep="grep --color"
alias e="emacs -nw --init-directory=$HOME/home_config/lisp"
alias ec=emacsclient
alias dn=dotnet
alias dnr="dotnet run"
alias ems="emacs -nw --eval '(progn (magit-status) (delete-other-windows))'"
alias idf=idf.py
alias idfini=". $HOME/.espressif/tools/activate_idf_v5.5.2.sh"
alias idfset="idf.py set-target esp32s3"
alias idfbld0="idf.py -p /dev/ttyACM0 build flash monitor"
alias idfbld1="idf.py -p /dev/ttyACM1 build flash monitor"

edf ()
{
    emacs -nw --eval "(ediff \"$1\" \"$2\")"
}

# if running bash
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

if [ "$OS" == "Windows_NT" ];
then
    echo ".profile Windows"

    alias p="/cygdrive/c/usr/Python35/python.exe"
    alias n="/cygdrive/c/Program\ Files/nodejs/node.exe"
else
    echo ".profile Linux"

    alias p="python3"
    alias m=make
    # alias n="node"
    
    #RUST_SRC_PATH=/mnt/src/rust-master/src
    PATH="$PATH:/opt/bin:/mnt/bin/gcc-arm/bin"
    export PATH
fi

if [ -f "$HOME/custom.sh" ] ; then
    . "$HOME/custom.sh"
fi


if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi


# Simple powerline
#
# Colors
RESET='\[\e[0m\]'

FG_BLACK='\[\e[30m\]'
FG_WHITE='\[\e[97m\]'
FG_CYAN='\[\e[36m\]'
FG_GREEN='\[\e[32m\]'
FG_YELLOW='\[\e[33m\]'
FG_RED='\[\e[31m\]'

BG_BLUE='\[\e[44m\]'
BG_CYAN='\[\e[46m\]'
BG_GREEN='\[\e[42m\]'
BG_YELLOW='\[\e[43m\]'
BG_RED='\[\e[41m\]'
BG_DEFAULT='\[\e[49m\]'

# Powerline separators (need a Nerd/Powerline font)
SEP_RIGHT=""
SEP_LEFT=""

# Git branch function
parse_git_branch() {
  git rev-parse --is-inside-work-tree &>/dev/null || return
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  [ -n "$branch" ] && echo "$branch"
}

# Exit status segment
exit_segment() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo -e "${BG_RED}${FG_WHITE} ✘ $exit_code ${RESET}${FG_RED}${BG_DEFAULT}$SEP_RIGHT${RESET}"
  fi
}

# Build PS1
PROMPT_DIRTRIM=3
PROMPT_COMMAND=__prompt_command
__prompt_command() {
  local EXIT="$?"  # capture exit code early

  # CWD segment
  local cwd="${BG_CYAN}${FG_BLACK} \w ${RESET}${FG_CYAN}${BG_DEFAULT}$SEP_RIGHT${RESET}"

  # Git segment
  local git_branch
  git_branch=$(parse_git_branch)
  local git_seg=""
  if [ -n "$git_branch" ]; then
    git_seg="${BG_GREEN}${FG_BLACK}  ${git_branch} ${RESET}${FG_GREEN}${BG_DEFAULT}$SEP_RIGHT${RESET}"
  fi

  # Exit code segment (if non-zero)
  local exit_seg=""
  if [ $EXIT -ne 0 ]; then
    exit_seg="${BG_RED}${FG_WHITE} ✘ ${EXIT} ${RESET}${FG_RED}${BG_DEFAULT}$SEP_RIGHT${RESET}"
  fi

  PS1="${cwd}${git_seg}${exit_seg} "
}
