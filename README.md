QUICKSHELL WI-FI MANAGER

A small Wi-Fi manager panel for Wayland, built with Quickshell and QML. It uses nmcli (NetworkManager) for everything, so there are no extra daemons or dependencies.

FEATURES

Toggle Wi-Fi on and off
Connected network card showing name and signal strength
Click the card to see details: security, band, channel, link speed, IP address, gateway, DNS, interface and BSSID
Disconnect from, or forget, the current network
Scrollable list of nearby networks, sorted by signal strength
Click a network to connect, with a password field for secured networks
Manual rescan button, plus automatic refresh every 5 seconds
Purple theme with a translucent background

REQUIREMENTS

Linux with a Wayland compositor (tested on Hyprland, Fedora)
Quickshell (https://quickshell.org)
NetworkManager (nmcli)
JetBrainsMono Nerd Font for the icons (https://www.nerdfonts.com)

INSTALLATION

Clone the repo into your Quickshell config folder:

git clone https://github.com/sabithskyrus/quickshell-config.git ~/.config/quickshell

If you already have a ~/.config/quickshell folder, copy just the wifi folder into it instead.

The layout should look like this:

~/.config/quickshell/wifi/shell.qml

USAGE

Launch the panel:

qs -c wifi -n

The -c wifi option selects the config folder, and -n prevents a second copy from opening if one is already running.

HYPRLAND KEYBIND

bind = $mainMod, W, exec, qs -c wifi -n

WAYBAR

Open the panel by clicking the network module. In your network module, set:

“on-click”: “qs -c wifi -n”

Reload Waybar afterwards with: pkill -SIGUSR2 waybar

HOW IT WORKS

Everything runs through Quickshell’s Process type, and the output is parsed in QML.

List networks: nmcli -t -f ACTIVE,SIGNAL,SECURITY,SSID dev wifi list
Connection details: nmcli -t -f ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY dev wifi list
IP, gateway, DNS: nmcli -t -f GENERAL,IP4 dev show
Wi-Fi on or off: nmcli radio wifi on (or off)
Rescan: nmcli dev wifi rescan
Connect: nmcli dev wifi connect SSID password PASSWORD
Disconnect: nmcli connection down id NAME
Forget: nmcli connection delete id NAME

CUSTOMIZATION

Colors: the accent color is bb9af7 and the background is A6161925. Colors in QML use AARRGGBB order (alpha first), with a hash sign in front in the code. Search and replace to change the theme.
Size: change implicitWidth and implicitHeight on the PanelWindow.
Position: change the anchors and margins on the PanelWindow.
Font: change font.family on the icon Text items if you use a different Nerd Font.

NOTES

Forget deletes the saved connection profile, including its password, so you will need to enter it again to reconnect.
Only Wi-Fi connections appear on the connected card. A wired connection shows as Not connected.
IPv4 details only. IPv6 is not shown.
