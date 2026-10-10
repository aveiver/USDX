#!/usr/bin/env bash
# Shortcut + autostart for the ui-v2 ("new look") build that is compiled
# in place in /home/karaoke/UltraStar (run it from game/ there).
#
# Unlike deploy-karaoke.sh this copies no game files and needs no sudo:
# run it as the karaoke user. The old "Karaoke" shortcut is left alone,
# so both versions stay in the app menu.
#
# Usage (as karaoke, from ~/UltraStar):
#   ./deploy/install-ui-v2-shortcut.sh                 app menu + desktop icon
#   ./deploy/install-ui-v2-shortcut.sh --autostart     also launch the new look
#                                                      at login (and stop the
#                                                      old one launching)
#   ./deploy/install-ui-v2-shortcut.sh --no-autostart  stop launching it at login
set -euo pipefail

AUTOSTART=""
for arg in "$@"; do
  case "$arg" in
    --autostart) AUTOSTART="enable" ;;
    --no-autostart) AUTOSTART="disable" ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$(id -un)" != "karaoke" ]; then
  echo "Run this as the karaoke user (su - karaoke), not $(id -un)." >&2
  exit 1
fi

FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="ultrastar-karaoke-v2"
DESKTOP_FILE="$FORK_DIR/deploy/$NAME.desktop"

if [ ! -x "$FORK_DIR/game/ultrastardx" ]; then
  echo "Note: $FORK_DIR/game/ultrastardx isn't built yet - run make first," \
       "the shortcut won't start anything until then."
fi

echo "Installing app menu entry and icon ..."
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps"
cp "$DESKTOP_FILE" "$HOME/.local/share/applications/$NAME.desktop"
cp "$FORK_DIR/deploy/ultrastar-karaoke.png" "$HOME/.local/share/icons/hicolor/256x256/apps/$NAME.png"
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

# icon on the desktop itself, marked as trusted so it launches on double-click
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
if [ -d "$DESKTOP_DIR" ]; then
  echo "Adding icon to $DESKTOP_DIR ..."
  cp "$DESKTOP_FILE" "$DESKTOP_DIR/$NAME.desktop"
  chmod +x "$DESKTOP_DIR/$NAME.desktop"
  gio set "$DESKTOP_DIR/$NAME.desktop" metadata::trusted true >/dev/null 2>&1 || true
fi

if [ "$AUTOSTART" = "enable" ]; then
  echo "Launching the new look at login (old version's autostart removed) ..."
  mkdir -p "$HOME/.config/autostart"
  cp "$DESKTOP_FILE" "$HOME/.config/autostart/$NAME.desktop"
  # only one karaoke should start at login
  rm -f "$HOME/.config/autostart/ultrastar-karaoke.desktop"
elif [ "$AUTOSTART" = "disable" ]; then
  echo "No longer launching the new look at login ..."
  rm -f "$HOME/.config/autostart/$NAME.desktop"
fi

echo "Done."
