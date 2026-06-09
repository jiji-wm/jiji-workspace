#!/bin/sh
set -e

# Removes both possible installed binary names. Post-compositor-rename, only
# jiji will be present; during the transition both may be on disk.

echo "Uninstalling compositor (niri and/or jiji)..."

for name in niri jiji; do
    sudo rm -f "/usr/local/bin/$name"
    sudo rm -f "/usr/local/bin/$name-session"
    sudo rm -f "/usr/local/share/wayland-sessions/$name.desktop"
    sudo rm -f "/usr/local/share/xdg-desktop-portal/$name-portals.conf"
    sudo rm -f "/etc/systemd/user/$name.service"
    sudo rm -f "/etc/systemd/user/$name-shutdown.target"
done

echo "Done."
