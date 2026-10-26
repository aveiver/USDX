#!/usr/bin/env bash
# Installs Demucs (AI vocal separator) into ~/vocal-remover, CPU only.
# Run once as the user that owns the songs (karaoke). Needs ~2 GB of disk.
set -euo pipefail

VENV="$HOME/vocal-remover"

# system packages: need an admin account, so only ask for them when missing
if ! command -v ffmpeg >/dev/null 2>&1 || ! python3 -c "import ensurepip" >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null || groups | grep -qw sudo; then
    sudo apt-get install -y python3-venv ffmpeg
  else
    echo "Missing system packages (ffmpeg / python3-venv). From your admin account run:"
    echo "  sudo apt-get install -y python3-venv ffmpeg"
    echo "then run this script again as $(whoami)."
    exit 1
  fi
fi

python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip
# pinned versions known to work together with demucs 4.0.1
"$VENV/bin/pip" install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu
"$VENV/bin/pip" install demucs==4.0.1 lameenc "numpy<2"

echo
echo "Installed. Try it on three songs first:"
echo "  $VENV/bin/python $(dirname "$(readlink -f "$0")")/make-instrumentals.py /home/karaoke/songs --limit 3"
