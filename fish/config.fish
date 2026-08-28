function ls
    command ls --group-directories-first --color=always $argv
end

function ll
    command ls --group-directories-first -lah --color=always $argv
end

function e
    command emacsclient -n -c $argv
end

function emacs
    command emacs --init-directory=$HOME/home_config/lisp $argv
end

function ems
    emacs -nw --eval '(progn (magit-status) (delete-other-windows))'
end

function grep
    command grep --color $argv
end

function du1
    command du --max-depth=1 $argv
end

function pip
    python3 -m pip $argv
end

function pt
    python3 -m pytest -v $argv
end

# Git shortcuts
function gs
    git status -s $argv
end

function gd
    git diff $argv
end

function gds
    git diff --staged $argv
end

function gl
    git log --oneline --graph --decorate -20 $argv
end

function gla
    git log --oneline --graph --decorate --all -20 $argv
end

# Directory navigation
function ..
    cd ..
end

function ...
    cd ../..
end

function ....
    cd ../../..
end

# Find and edit helpers
function ff
    find . -name "*$argv[1]*" 2>/dev/null
end

function edf
    emacs -nw --eval "(ediff \"$argv[1]\" \"$argv[2]\")"
end
