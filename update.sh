#!/bin/sh

mkdir ~/.config/awesome
ln -s ~/home_config/awesome/rc.lua ~/.config/awesome/rc.lua
ln -s ~/home_config/awesome/system_monitor.lua ~/.config/awesome/system_monitor.lua

mkdir ~/.config/sway
ln -s ~/home_config/sway/config ~/.config/sway/config

mkdir ~/.config/waybar
ln -s ~/home_config/waybar/config ~/.config/waybar/config
ln -s ~/home_config/waybar/style.css ~/.config/waybar/style.css

mkdir ~/.config/foot
ln -s ~/home_config/foot/foot.ini ~/.config/foot/foot.ini

ln -s ~/home_config/kitty ~/.config/kitty

mkdir ~/.config/fish
ln -s ~/home_config/fish/config.fish ~/.config/fish/config.fish
mkdir ~/.config/fish/functions
ln -s ~/home_config/fish/functions/fish_prompt.fish ~/.config/fish/functions/fish_prompt.fish

ln -s ~/home_config/xinitrc ~/.xinitrc

# sudoers.d drop-ins must be root-owned and mode 0440, so they're installed
# (not symlinked) and validated with visudo before being put in place.
for f in ~/home_config/sudoers.d/*; do
  name=$(basename "$f")
  sudo visudo -c -f "$f" && sudo install -m 0440 -o root -g root "$f" "/etc/sudoers.d/$name"
done
