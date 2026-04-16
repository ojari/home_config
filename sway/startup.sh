#!/bin/bash
set -e

# Launch apps only if not already running
pgrep foot >/dev/null || swaymsg "exec foot"
pgrep foot >/dev/null || swaymsg "exec foot"
pgrep code >/dev/null || swaymsg "exec code"
pgrep firefox >/dev/null || swaymsg "exec firefox"
pgrep slack >/dev/null || swaymsg "exec slack"
pgrep evolution >/dev/null || swaymsg "exec evolution"
#pgrep emacs >/dev/null || swaymsg "emacs --init-directory=/home/jari/home_config/lisp"
pgrep obsidian >/dev/null || swaymsg "exec /home/jari/bin/obsidian/obsidian"
