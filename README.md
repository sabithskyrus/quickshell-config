MY DOTFILES

Personal configuration files for my Linux desktop. Right now this repo holds my Quickshell setup: a set of small panels that I open from my bar or with keybinds.

WHAT’S INSIDE

Each panel lives in its own folder inside the Quickshell config directory, with a shell.qml file in it:

~/.config/quickshell/
wifi/shell.qml
bluetooth/shell.qml

More folders will be added here as I build more panels.

MY SETUP

OS: Fedora
Compositor: Hyprland
Bar: Waybar
Shell toolkit: Quickshell (QML)
Font: JetBrainsMono Nerd Font
Theme: translucent dark background with a purple accent

REQUIREMENTS

A Wayland compositor
Quickshell (https://quickshell.org)
JetBrainsMono Nerd Font (https://www.nerdfonts.com), used for the icons
Whatever system tools a panel calls. These are listed in the commands near the top of its shell.qml.

INSTALLATION

Clone the repo into your Quickshell config folder:

git clone https://github.com/sabithskyrus/quickshell-config.git ~/.config/quickshell

If you already have a ~/.config/quickshell folder, copy just the folders you want into it instead.

USAGE

Launch any panel by its folder name:

qs -c NAME -n

NAME is the folder, for example wifi. The -c option picks the config, and -n stops a second copy from opening if one is already running.

Hyprland keybind example:

bind = $mainMod, W, exec, qs -c wifi -n

Waybar example, added to any module:

“on-click”: “qs -c wifi -n”

After editing the Waybar config, reload it with: pkill -SIGUSR2 waybar

CUSTOMIZING

Colors: the accent color is bb9af7 and the background is A6161925. QML colors use AARRGGBB order, with the alpha first and a hash sign in front in the code.
Size: change implicitWidth and implicitHeight on the PanelWindow.
Position: change the anchors and margins on the PanelWindow.
Font: change font.family on the icon Text items if you use a different Nerd Font.

NOTES

Panels are tuned for my machine, so you may need to tweak a few things.
Some panels run system commands, so read a shell.qml before running it.

ROADMAP

More panels (volume, power menu and others)
A shared theme file so colors can be changed in one place
Screenshots
