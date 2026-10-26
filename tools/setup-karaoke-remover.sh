#!/usr/bin/env bash
# Installs python-audio-separator (lead-vocal "karaoke" models, backing vocals
# kept) into ~/karaoke-remover. Run once as the user that owns the songs.
# Uses an NVIDIA graphics card if there is one (much faster), else the CPU.
# Needs ~3-5 GB of disk; the models (~1 GB) download on first use.
set -euo pipefail

VENV="$HOME/karaoke-remover"

if ! command -v ffmpeg >/dev/null 2>&1 || ! python3 -c "import ensurepip" >/dev/null 2>&1; then
  echo "Missing system packages (ffmpeg / python3-venv). From your admin account run:"
  echo "  sudo apt-get install -y python3-venv ffmpeg"
  echo "then run this script again as $(whoami)."
  exit 1
fi

python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  echo "NVIDIA card found - installing the GPU version"
  "$VENV/bin/pip" install torch torchvision
  "$VENV/bin/pip" install "audio-separator[gpu]"
else
  echo "No NVIDIA card - installing the CPU version"
  "$VENV/bin/pip" install torch torchvision --index-url https://download.pytorch.org/whl/cpu
  "$VENV/bin/pip" install "audio-separator[cpu]"
  # dependencies can pull a mismatched (CUDA) torchvision from PyPI; put the
  # matching CPU pair back ("operator torchvision::nms does not exist")
  "$VENV/bin/pip" install --force-reinstall --no-deps torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi
# audioread is imported by audio-separator but not listed as a dependency
"$VENV/bin/pip" install audioread
mkdir -p "$VENV/models"

if ! "$VENV/bin/audio-separator" --list_presets 2>/dev/null | grep -q '^karaoke'; then
  echo "WARNING: this audio-separator version has no 'karaoke' preset."
  echo "Use a single model instead, e.g. --model mel_band_roformer_karaoke_gabox_v2.ckpt"
fi

echo
echo "Installed. Time one song first (the first run also downloads the models):"
echo "  $VENV/bin/python $(dirname "$(readlink -f "$0")")/make-instrumentals.py --keep-backing --limit 1 /home/karaoke/songs"
