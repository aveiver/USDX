#!/usr/bin/env bash
# Installs Demucs (AI vocal separator) into ~/vocal-remover, CPU only.
# Run once as the user that owns the songs (karaoke). Needs ~2 GB of disk.
set -euo pipefail

VENV="$HOME/vocal-remover"

sudo apt-get install -y python3-venv ffmpeg

python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip
# pinned versions known to work together with demucs 4.0.1
"$VENV/bin/pip" install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu
"$VENV/bin/pip" install demucs==4.0.1 lameenc "numpy<2"

echo
echo "Installed. Try it on three songs first:"
echo "  $VENV/bin/python $(dirname "$(readlink -f "$0")")/make-instrumentals.py /home/karaoke/songs --limit 3"
