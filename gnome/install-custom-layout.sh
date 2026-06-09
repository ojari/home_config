#!/usr/bin/env sh

SYMBOLS_FILE="/usr/share/X11/xkb/symbols/fi"

sudo cp "$SYMBOLS_FILE" "$SYMBOLS_FILE.bak.$(date +%Y%m%d%H%M%S)"
sudo cp fi "$SYMBOLS_FILE"

