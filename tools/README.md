# Backing tracks (vocals removed)

The game can play a song's backing track instead of the original vocals when
the song's .txt has an `#INSTRUMENTAL:` line pointing at a vocals-free copy.
These scripts make those copies for the whole library with Demucs, an AI
vocal separator. It runs on your PC, so nothing gets uploaded anywhere.

## One-off setup (as the karaoke user)

    ~/UltraStar/tools/setup-vocal-remover.sh

## Make the backing tracks

Try three songs first:

    ~/vocal-remover/bin/python ~/UltraStar/tools/make-instrumentals.py /home/karaoke/songs --limit 3

Then do the rest. It takes a while on a CPU, so leave it running overnight. You
can stop it and run it again later, because finished songs are skipped:

    ~/vocal-remover/bin/python ~/UltraStar/tools/make-instrumentals.py /home/karaoke/songs

* `--dry-run` lists what would be done.
* `--model htdemucs_ft` is a little cleaner but about 4x slower.
* The original .txt files are copied to `~/song-txt-backups` first.

## Using it in the game

* **Options > Sound > Vocals Volume** sets the mix: 0% = backing track only,
  100% = the original song. It is remembered.
* The **Vocals** switch at the top of the song list (next to Scoring) turns
  the original vocals on or off.
* Songs without a backing track just play normally.
