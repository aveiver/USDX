#!/usr/bin/env bash
# Starts the ui-v2 build together with the phone song queue.
#
# The queue server (remote/karaoke_remote.py) is started in the background
# if it isn't running yet, then the game itself. Guests on the same Wi-Fi
# open the address shown on the main menu (or scan its QR code).
DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

mkdir -p "$DIR/game/remote"
# (re)start the queue server so a git pull or a changed public-url.txt
# always takes effect
pkill -f "remote/run-queue.sh" >/dev/null 2>&1
pkill -f "remote/karaoke_remote.py" >/dev/null 2>&1 && sleep 1
# run-queue.sh restarts the server if it ever stops; the log is kept
# (appended) so a problem during a party can be looked at afterwards
nohup "$DIR/remote/run-queue.sh" "$DIR/game/remote" >/dev/null 2>&1 &

cd "$DIR/game"
exec ./ultrastardx "$@"
