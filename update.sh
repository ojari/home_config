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

ln -s ~/home_config/xinitrc ~/.xinitrc
