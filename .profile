#!/bin/sh

alias ls="ls --color=always"
alias ll="ls -la"
alias du1="du --max-depth=1"

if [ "$OS" == "Windows_NT" ];
then
    echo ".profile Windows"

    alias p="/cygdrive/c/usr/Python35/python.exe"
    alias n="/cygdrive/c/Program\ Files/nodejs/node.exe"
else
    echo ".profile Linux"

    alias p="python"
    alias m=make
    alias n="node"
    alias e="/usr/bin/emacs"
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
