#!/bin/sh

echo ".profile"

alias ls="ls --color=always"
alias ll="ls -la"
alias du1="du --max-depth=1"

if [ $OS == "Windows_NT" ];
then
    echo "Windows"

    alias p="/cygdrive/c/usr/Python35/python.exe"
    alias n="/cygdrive/c/Program\ Files/nodejs/node.exe"
else
    echo "Linux"

    alias p="python"
    alias m=make
    alias n="node"
    alias e="/usr/bin/emacs"
fi
