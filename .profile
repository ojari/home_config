#!/bin/sh

# Directory color (di) overridden to Zenburn's cyan (#8cd0d3) via 24-bit
# truecolor SGR, since the default bold-blue di=01;34 renders as a jarringly
# vivid bright blue against kitty's Zenburn theme (color12 #94bff3) instead
# of matching the theme's own muted palette.
export LS_COLORS="rs=0:di=01;38;2;140;208;211:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=01;37;41:su=37;41:sg=30;43:ca=00:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.7z=01;31:*.ace=01;31:*.alz=01;31:*.apk=01;31:*.arc=01;31:*.arj=01;31:*.bz=01;31:*.bz2=01;31:*.cab=01;31:*.cpio=01;31:*.crate=01;31:*.deb=01;31:*.drpm=01;31:*.dwm=01;31:*.dz=01;31:*.ear=01;31:*.egg=01;31:*.esd=01;31:*.gz=01;31:*.jar=01;31:*.lha=01;31:*.lrz=01;31:*.lz=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.lzo=01;31:*.pyz=01;31:*.rar=01;31:*.rpm=01;31:*.rz=01;31:*.sar=01;31:*.swm=01;31:*.t7z=01;31:*.tar=01;31:*.taz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tgz=01;31:*.tlz=01;31:*.txz=01;31:*.tz=01;31:*.tzo=01;31:*.tzst=01;31:*.udeb=01;31:*.war=01;31:*.whl=01;31:*.wim=01;31:*.xz=01;31:*.z=01;31:*.zip=01;31:*.zoo=01;31:*.zst=01;31:*.avif=01;35:*.jpg=01;35:*.jpeg=01;35:*.jxl=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.webp=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=01;36:*.au=01;36:*.flac=01;36:*.m4a=01;36:*.mid=01;36:*.midi=01;36:*.mka=01;36:*.mp3=01;36:*.mpc=01;36:*.ogg=01;36:*.ra=01;36:*.wav=01;36:*.oga=01;36:*.opus=01;36:*.spx=01;36:*.xspf=01;36:*~=00;90:*#=00;90:*.bak=00;90:*.crdownload=00;90:*.dpkg-dist=00;90:*.dpkg-new=00;90:*.dpkg-old=00;90:*.dpkg-tmp=00;90:*.old=00;90:*.orig=00;90:*.part=00;90:*.rej=00;90:*.rpmnew=00;90:*.rpmorig=00;90:*.rpmsave=00;90:*.swp=00;90:*.tmp=00;90:*.ucf-dist=00;90:*.ucf-new=00;90:*.ucf-old=00;90:"

alias ls="ls --color=always --group-directories-first --hyperlink=auto"
alias ll="ls -lAh"
alias du1="du --max-depth=1"
alias grep="grep --color"
alias e="emacs -nw --init-directory=$HOME/home_config/lisp"
alias emacs="emacs --init-directory=$HOME/home_config/lisp"
# alias ec=emacsclient
# alias dn=dotnet
# alias dnr="dotnet run"
alias ems="emacs -nw --eval '(progn (magit-status) (delete-other-windows))'"

alias pip="python3 -m pip"
alias pt="python3 -m pytest -v"

# Git shortcuts
alias gs="git status -s"
alias gd="git diff"
alias gds="git diff --staged"
alias gl="git log --oneline --graph --decorate -20"
alias gla="git log --oneline --graph --decorate --all -20"

# Directory navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Find and grep helpers
ff() { find . -name "*$1*" 2>/dev/null; }

edf ()
{
    emacs -nw --eval "(ediff \"$1\" \"$2\")"
}

if [ "$OS" == "Windows_NT" ];
then
    echo ".profile Windows"
else
    echo ".profile Linux"

    #RUST_SRC_PATH=/mnt/src/rust-master/src
    PATH="$PATH:/opt/bin:/mnt/bin/gcc-arm/bin"
    export PATH
fi

if [ -f "$HOME/custom.sh" ] ; then
    . "$HOME/custom.sh"
fi

if [ -f "$HOME/home_config/punta.sh" ] ; then
    . "$HOME/home_config/punta.sh"
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
