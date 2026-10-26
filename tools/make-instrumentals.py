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

With --keep-backing the lead singer only is removed and backing vocals
stay in, using a combination of three "karaoke" models (python-audio-separator,
set up by setup-karaoke-remover.sh). Much slower, better result. Those files
are named "... [Karaoke].mp3" and replace the plain backing track in the .txt
(the old file stays on disk).

Safe to stop and run again: songs that already have a backing track are
skipped. Each .txt is backed up before it's changed.

    ~/vocal-remover/bin/python make-instrumentals.py /home/karaoke/songs
    ~/karaoke-remover/bin/python make-instrumentals.py --keep-backing /home/karaoke/songs
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


def separate_karaoke(python, model, audio, workdir):
    """Removes the lead vocal only (backing vocals stay); returns the mp3 path.

    model is an audio-separator ensemble preset name ('karaoke') or a single
    model file name."""
    # decode with ffmpeg first: handles mp4/m4a and keeps the timing the game uses
    wav = os.path.join(workdir, 'input.wav')
    res = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', audio,
                          '-vn', '-ac', '2', '-ar', '44100', wav],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if res.returncode != 0 or not os.path.isfile(wav):
        raise RuntimeError('ffmpeg could not read the audio: ' +
                           res.stdout.decode('utf-8', 'replace').strip()[-300:])

    tool = os.path.join(os.path.dirname(python), 'audio-separator')
    if not os.path.isfile(tool):
        raise RuntimeError('audio-separator not found next to ' + python +
                           ' (run setup-karaoke-remover.sh, or pass --python)')
    out_dir = os.path.join(workdir, 'out')
    cmd = [tool, wav, '--output_dir', out_dir, '--output_format', 'MP3',
           '--output_bitrate', '256k',
           '--model_file_dir', os.path.expanduser('~/karaoke-remover/models'),
           '--custom_output_names', '{"Instrumental": "instrumental", "Vocals": "lead"}']
    if model.endswith(('.ckpt', '.onnx', '.pth', '.yaml')):
        cmd += ['-m', model]
    else:
        cmd += ['--ensemble_preset', model]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    found = []
    for root, _d, files in os.walk(out_dir):
        found += [os.path.join(root, f) for f in files]
    for f in found:
        base = os.path.basename(f).lower()
        if base.startswith('instrumental.') or '(instrumental)' in base:
            return f
    tail = res.stdout.decode('utf-8', 'replace').strip().splitlines()[-8:]
    raise RuntimeError('audio-separator made no instrumental (got: %s)\n    %s'
                       % (', '.join(os.path.basename(f) for f in found) or 'nothing',
                          '\n    '.join(tail)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('songs', help='songs folder, e.g. /home/karaoke/songs')
    ap.add_argument('--keep-backing', action='store_true',
                    help='remove only the lead singer, keep backing vocals (slow)')
    ap.add_argument('--python', default=sys.executable,
                    help='python that has demucs / audio-separator installed (default: this one)')
    ap.add_argument('--model', default=None,
                    help='demucs: htdemucs (default) or htdemucs_ft; '
                         '--keep-backing: karaoke (default, 3-model ensemble) or one model file, '
                         'e.g. mel_band_roformer_karaoke_gabox_v2.ckpt (about 3x faster)')
    ap.add_argument('--backup', default=os.path.expanduser('~/song-txt-backups'),
                    help='where the original .txt files are copied before changing them')
    ap.add_argument('--limit', type=int, default=0, help='stop after this many songs')
    ap.add_argument('--dry-run', action='store_true', help='only list what would be done')
    args = ap.parse_args()
    if args.model is None:
        args.model = 'karaoke' if args.keep_backing else 'htdemucs'
    suffix = ' [Karaoke].mp3' if args.keep_backing else ' [Instrumental].mp3'

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
                # with --keep-backing, plain backing tracks get upgraded
                if not args.keep_backing or tags['INSTRUMENTAL'][1].endswith(suffix):
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
    run_start = time.time()
    for n, (txt, audio, audio_tag) in enumerate(todo, 1):
        folder = os.path.dirname(txt)
        rel = os.path.relpath(txt, songs_root)
        print('[%d/%d] %s' % (n, len(todo), rel), flush=True)
        started = time.time()
        try:
            name = safe_stem(os.path.basename(audio)) + suffix
            dest = os.path.join(folder, name)
            # several .txt files (e.g. solo and duet versions) can share one
            # audio file: separate it once and reuse the backing track
            if os.path.isfile(dest) and os.path.getmtime(dest) >= os.path.getmtime(audio):
                print('    reusing the backing track made for this audio', flush=True)
            else:
                with tempfile.TemporaryDirectory(prefix='instr-') as work:
                    if args.keep_backing:
                        made = separate_karaoke(args.python, args.model, audio, work)
                    else:
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
            # replace an old #INSTRUMENTAL line (missing file, or the plain one)
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
            left = (time.time() - run_start) / n * (len(todo) - n)
            print('    ok (%ds) -> %s   [about %dh%02dm to go]'
                  % (time.time() - started, name, left // 3600, left % 3600 // 60), flush=True)
        except Exception as e:  # keep going with the next song
            failed += 1
            print('    FAILED: %s' % e, flush=True)

    print('\nDone: %d made, %d failed. Originals of changed .txt files are in %s'
          % (done, failed, args.backup))
    if done:
        print('Restart the game (or rescan songs) to pick them up.')


if __name__ == '__main__':
    main()
