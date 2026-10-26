#!/usr/bin/env python3
"""
Make backing tracks (vocals removed) for UltraStar songs.

For every song .txt under the songs folder that has no #INSTRUMENTAL yet,
the song's audio (#AUDIO / #MP3, mp3 or mp4 alike) is split with Demucs,
an AI vocal separator, and the music without the vocals is saved next to it
as "<audio name> [Instrumental].mp3". The .txt then gets a line

    #INSTRUMENTAL:<audio name> [Instrumental].mp3

which the game picks up: it plays both tracks in sync and the "Vocals
Volume" setting (Options > Sound, or the K key while singing) decides how
much of the original vocals you hear.

Safe to stop and run again: songs that already have a backing track are
skipped. Each .txt is backed up before it's changed.

    ~/vocal-remover/bin/python make-instrumentals.py /home/karaoke/songs
    ... --dry-run          list what would be done
    ... --limit 3          only do the first 3 songs (to try it out)
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata

NOTE_LINE = re.compile(rb'^\s*[:*FRG\-PE]')


def decode(raw):
    for enc in ('utf-8-sig', 'cp1252', 'latin-1'):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            pass
    return raw.decode('latin-1'), 'latin-1'


def read_header(lines):
    """tag name -> (line index, value as text, encoding) for the header."""
    tags = {}
    for i, line in enumerate(lines):
        if NOTE_LINE.match(line) and not line.lstrip().startswith(b'#'):
            break
        s = line.strip()
        if i == 0 and s.startswith(b'\xef\xbb\xbf'):
            s = s[3:]
        if not s.startswith(b'#') or b':' not in s:
            continue
        name, value = s[1:].split(b':', 1)
        text, enc = decode(value.strip())
        tags.setdefault(name.strip().upper().decode('ascii', 'replace'), (i, text, enc))
    return tags


def safe_stem(name):
    stem = os.path.splitext(name)[0]
    stem = unicodedata.normalize('NFKD', stem).encode('ascii', 'ignore').decode('ascii')
    stem = re.sub(r'[\\/:*?"<>|]+', '', stem).strip()
    return stem or 'song'


def separate(python, model, audio, workdir):
    """Runs Demucs; returns the path of the vocals-free mp3 it wrote."""
    cmd = [python, '-m', 'demucs', '--two-stems', 'vocals', '-n', model,
           '--mp3', '--mp3-bitrate', '256', '-o', workdir,
           '--filename', '{stem}.{ext}', audio]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = os.path.join(workdir, model, 'no_vocals.mp3')
    if res.returncode != 0 or not os.path.isfile(out):
        tail = res.stdout.decode('utf-8', 'replace').strip().splitlines()[-8:]
        raise RuntimeError('demucs failed:\n    ' + '\n    '.join(tail))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('songs', help='songs folder, e.g. /home/karaoke/songs')
    ap.add_argument('--python', default=sys.executable,
                    help='python that has demucs installed (default: this one)')
    ap.add_argument('--model', default='htdemucs',
                    help='demucs model (htdemucs = good and quick, htdemucs_ft = best, ~4x slower)')
    ap.add_argument('--backup', default=os.path.expanduser('~/song-txt-backups'),
                    help='where the original .txt files are copied before changing them')
    ap.add_argument('--limit', type=int, default=0, help='stop after this many songs')
    ap.add_argument('--dry-run', action='store_true', help='only list what would be done')
    args = ap.parse_args()

    songs_root = os.path.abspath(args.songs)
    todo = []
    for folder, _dirs, files in os.walk(songs_root):
        for f in sorted(files):
            if not f.lower().endswith('.txt'):
                continue
            txt = os.path.join(folder, f)
            with open(txt, 'rb') as fh:
                raw = fh.read()
            lines = raw.split(b'\n')
            tags = read_header(lines)
            if 'INSTRUMENTAL' in tags and os.path.isfile(os.path.join(folder, tags['INSTRUMENTAL'][1])):
                continue
            audio_tag = 'AUDIO' if 'AUDIO' in tags else 'MP3' if 'MP3' in tags else None
            if audio_tag is None:
                continue  # not a song file
            audio = os.path.join(folder, tags[audio_tag][1])
            if not os.path.isfile(audio):
                print('skip (audio file missing): ' + os.path.relpath(txt, songs_root))
                continue
            todo.append((txt, audio, audio_tag))

    print('%d song(s) need a backing track' % len(todo))
    if args.limit:
        todo = todo[:args.limit]
    if args.dry_run:
        for txt, audio, _ in todo:
            print('  ' + os.path.relpath(txt, songs_root))
        return

    done = failed = 0
    for n, (txt, audio, audio_tag) in enumerate(todo, 1):
        folder = os.path.dirname(txt)
        rel = os.path.relpath(txt, songs_root)
        print('[%d/%d] %s' % (n, len(todo), rel), flush=True)
        started = time.time()
        try:
            name = safe_stem(os.path.basename(audio)) + ' [Instrumental].mp3'
            dest = os.path.join(folder, name)
            # several .txt files (e.g. solo and duet versions) can share one
            # audio file: separate it once and reuse the backing track
            if os.path.isfile(dest) and os.path.getmtime(dest) >= os.path.getmtime(audio):
                print('    reusing the backing track made for this audio', flush=True)
            else:
                with tempfile.TemporaryDirectory(prefix='instr-') as work:
                    made = separate(args.python, args.model, audio, work)
                    shutil.move(made, dest)

            # back up the .txt, then add the tag under the audio line
            bak = os.path.join(args.backup, rel)
            os.makedirs(os.path.dirname(bak), exist_ok=True)
            if not os.path.exists(bak):
                shutil.copy2(txt, bak)
            with open(txt, 'rb') as fh:
                raw = fh.read()
            lines = raw.split(b'\n')
            tags = read_header(lines)
            eol = b'\r' if lines[0].endswith(b'\r') else b''
            # drop a stale #INSTRUMENTAL pointing at a missing file
            if 'INSTRUMENTAL' in tags:
                del lines[tags['INSTRUMENTAL'][0]]
                tags = read_header(lines)
            idx, _, enc = tags[audio_tag]
            enc = 'utf-8' if enc == 'utf-8-sig' else enc
            lines.insert(idx + 1, b'#INSTRUMENTAL:' + name.encode(enc) + eol)
            tmp = txt + '.tmp'
            with open(tmp, 'wb') as fh:
                fh.write(b'\n'.join(lines))
            shutil.copymode(txt, tmp)
            os.replace(tmp, txt)
            done += 1
            print('    ok (%ds) -> %s' % (time.time() - started, name), flush=True)
        except Exception as e:  # keep going with the next song
            failed += 1
            print('    FAILED: %s' % e, flush=True)

    print('\nDone: %d made, %d failed. Originals of changed .txt files are in %s'
          % (done, failed, args.backup))
    if done:
        print('Restart the game (or rescan songs) to pick them up.')


if __name__ == '__main__':
    main()
