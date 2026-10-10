#!/usr/bin/env bash
# Sets the Midnight karaoke wallpaper for the user running it (GNOME/Ubuntu).
# Run it as the karaoke user, from a terminal in their desktop session.
set -euo pipefail
FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.local/share/backgrounds/karaoke-wallpaper.png"

mkdir -p "$(dirname "$DEST")"
cp "$FORK_DIR/deploy/karaoke-wallpaper.png" "$DEST"
gsettings set org.gnome.desktop.background picture-uri "file://$DEST"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$DEST"
gsettings set org.gnome.desktop.background picture-options 'zoom'
gsettings set org.gnome.desktop.background primary-color '#0D0E12'
gsettings set org.gnome.desktop.screensaver picture-uri "file://$DEST" 2>/dev/null || true
echo "Wallpaper set."
