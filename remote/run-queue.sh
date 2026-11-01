#!/usr/bin/env bash
# Keeps the karaoke queue server running: if it ever stops, it is started
# again after a couple of seconds. Started by deploy/launch-ui-v2.sh.
#   run-queue.sh <shared folder>
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DIR="$1"
LOG="$DIR/server.log"
while true; do
  # keep the log from growing without end: keep the last 2000 lines
  if [ -f "$LOG" ] && [ "$(wc -l <"$LOG")" -gt 4000 ]; then
    tail -n 2000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
  python3 -u "$HERE/karaoke_remote.py" --dir "$DIR" >>"$LOG" 2>&1
  CODE=$?
  echo "$(date '+%Y-%m-%d %H:%M:%S') queue server stopped (exit $CODE), restarting" >>"$LOG"
  sleep 2
done
