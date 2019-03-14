#!/bin/sh

alias ls="ls --color=always --group-directories-first"
alias ec="tmux select-window -t 2 && emacsclient"
alias ll="ls -lAh"
alias du1="du --max-depth=1"
alias ta="tmux attach"
alias grep="grep --color"
alias bb="bitbake"
alias emacs=/opt/bin/emacs
alias e=/opt/bin/emacs

if [ "$OS" == "Windows_NT" ];
then
    echo ".profile Windows"

    alias p="/cygdrive/c/usr/Python35/python.exe"
    alias n="/cygdrive/c/Program\ Files/nodejs/node.exe"
else
    echo ".profile Linux"

    alias p="python3"
    alias m=make
    alias n="node"
    alias e="/usr/bin/emacs"
    
    RUST_SRC_PATH=/mnt/src/rust-master/src
    PATH="$PATH:/opt/rust/bin:/mnt/bin/gcc-arm/bin"
fi

# if running bash
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi
