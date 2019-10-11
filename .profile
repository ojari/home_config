#!/bin/sh

alias ls="ls --color=always --group-directories-first"
alias ec="tmux select-window -t 2 && emacsclient"
alias ll="ls -lAh"
alias du1="du --max-depth=1"
alias ta="tmux attach"
alias grep="grep --color"
alias bb="bitbake"
alias e=emacs
alias ec=emacsclient
alias ems="emacs -nw --eval '(progn (magit-status) (delete-other-windows))'"

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
    alias n="node"
    
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
