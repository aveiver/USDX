#!/usr/bin/env bash
# Deploys the current build of this fork's game/ folder to the dedicated
# "karaoke" kiosk user account on this machine, and (re)installs the
# desktop shortcut + icon it uses to launch the game.
#
# This does NOT build the game - run the normal build first so game/
# is up to date, then run this script.
#
# Requires sudo (writes into /home/karaoke/...).
set -euo pipefail

FORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/home/karaoke/usdx-build"

echo "Syncing build from $FORK_DIR/game to $BUILD_DIR ..."
sudo rsync -a --delete \
  --exclude=songs \
  --exclude=playlists \
  --exclude=avatar.db \
  --exclude=covers \
  --exclude=screenshots \
  --exclude=Ultrastar.db \
  --exclude=config.ini \
  --exclude=Error.log \
  "$FORK_DIR/game/" "$BUILD_DIR/"

sudo chown -R karaoke:karaoke "$BUILD_DIR"

echo "Installing desktop shortcut and icon ..."
sudo mkdir -p /home/karaoke/.local/share/applications
sudo mkdir -p /home/karaoke/.local/share/icons/hicolor/256x256/apps

sudo cp "$FORK_DIR/deploy/ultrastar-karaoke.desktop" /home/karaoke/.local/share/applications/ultrastar-karaoke.desktop
sudo cp "$FORK_DIR/deploy/ultrastar-karaoke.png" /home/karaoke/.local/share/icons/hicolor/256x256/apps/ultrastar-karaoke.png

sudo chown karaoke:karaoke /home/karaoke/.local/share/applications/ultrastar-karaoke.desktop
sudo chown -R karaoke:karaoke /home/karaoke/.local/share/icons

sudo gtk-update-icon-cache -f -t /home/karaoke/.local/share/icons/hicolor || true

echo "Done. karaoke's own data (songs, config.ini, Ultrastar.db, avatars, covers, screenshots, playlists, Error.log) was left untouched."
