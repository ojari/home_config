#!/bin/bash
set -e

host="$(hostname)"

# Launch apps only if not already running
pgrep foot >/dev/null || swaymsg "exec foot"
pgrep firefox >/dev/null || swaymsg "exec firefox"
pgrep emacs >/dev/null || swaymsg "exec emacs --init-directory=/home/jari/home_config/lisp"
pgrep obsidian >/dev/null || swaymsg "exec /home/jari/bin/obsidian/obsidian"
pgrep keepassxc >/dev/null || swaymsg "exec keepassxc"

case "$host" in
    fedora)
        pgrep code >/dev/null || swaymsg "exec code"
        pgrep slack >/dev/null || swaymsg "exec slack"
        # pgrep evolution >/dev/null || swaymsg "exec evolution"
        pgrep google-chrome >/dev/null || swaymsg "exec /opt/google/chrome/google-chrome --profile-directory=Default --app-id=pkooggnaalmfkidjmlhoelhdllpphaga"
        ;;
	yoga)

		;;
    *)
        # TBD: apps for other hosts
        ;;
esac
