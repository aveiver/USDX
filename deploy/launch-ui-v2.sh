#!/usr/bin/env bash
# Starts the ui-v2 build together with the phone song queue.
#
# The queue server (remote/karaoke_remote.py) is started in the background
# if it isn't running yet, then the game itself. Guests on the same Wi-Fi
# open the address shown on the main menu (or scan its QR code).
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

mkdir -p "$DIR/game/remote"
if ! pgrep -f "remote/karaoke_remote.py" >/dev/null 2>&1; then
  nohup python3 "$DIR/remote/karaoke_remote.py" --dir "$DIR/game/remote" \
    >"$DIR/game/remote/server.log" 2>&1 &
fi

cd "$DIR/game"
exec ./ultrastardx "$@"
